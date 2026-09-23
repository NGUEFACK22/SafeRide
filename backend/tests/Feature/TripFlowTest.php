<?php

namespace Tests\Feature;

use App\Models\QrCode;
use App\Models\Role;
use App\Models\Trip;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class TripFlowTest extends TestCase
{
    use RefreshDatabase;

    private function user(string $email, string $telephone, string $roleSlug): User
    {
        $role = Role::firstOrCreate(['slug' => $roleSlug], ['nom' => ucfirst($roleSlug)]);
        $user = User::create([
            'nom' => 'Test',
            'prenom' => 'User',
            'email' => $email,
            'telephone' => $telephone,
            'password' => Hash::make('password'),
        ]);
        $user->roles()->attach($role);

        return $user;
    }

    public function test_full_trip_lifecycle(): void
    {
        Http::fake(['*' => Http::response('', 500)]);
        config(['services.ai.enabled' => false]);

        $transporteur = $this->user('transporteur@example.com', '690000010', 'transporteur');
        $passager = $this->user('passager@example.com', '690000011', 'passager');

        // 1. Le transporteur ajoute un véhicule → QR signé généré.
        $vehicle = $this->actingAs($transporteur)->postJson('/api/v1/vehicles', [
            'marque' => 'Toyota',
            'modele' => 'Corolla',
            'immatriculation' => 'LT-777-AB',
            'type' => 'VOITURE',
        ])->assertCreated()->json('vehicle');

        $this->assertNotNull($vehicle['qr_codes'][0]['token'] ?? null);

        // 1b. Le transporteur partage sa position (requis pour proximité 50m — P1-1)
        $this->actingAs($transporteur)->postJson("/api/v1/vehicles/{$vehicle['id']}/position", [
            'latitude' => 3.8480,
            'longitude' => 11.5021,
        ])->assertOk();

        // 2. Le passager scanne le QR → SCANNE.
        $startResponse = $this->actingAs($passager)->postJson('/api/v1/trips/start', [
            'token' => $vehicle['qr_codes'][0]['token'],
            'latitude' => 3.8480,
            'longitude' => 11.5021,
        ])->assertCreated();
        $start = $startResponse->json('trip');

        $this->assertEquals('SCANNE', $start['statut']);

        // 2b. Le transporteur est exposé avec ses informations complètes :
        // nom, email, téléphone, nombre de courses et avis des passagers.
        $exposedTransporteur = $startResponse->json('transporteur');
        $this->assertNotNull($exposedTransporteur);
        $this->assertEquals('Test', $exposedTransporteur['nom']);
        $this->assertEquals('transporteur@example.com', $exposedTransporteur['email']);
        $this->assertEquals('690000010', $exposedTransporteur['telephone']);
        $this->assertArrayHasKey('trips_count', $exposedTransporteur);
        $this->assertIsArray($exposedTransporteur['reviews']);

        // 3. Le passager accepte de démarrer → EN_ATTENTE_TRANSPORTEUR.
        $confirm = $this->postJson("/api/v1/trips/{$start['id']}/confirm-embarquement")
            ->assertOk()->json('trip');
        $this->assertEquals('EN_ATTENTE_TRANSPORTEUR', $confirm['statut']);

        // 3b. Le transporteur accepte la course → CONFIRME.
        $accepted = $this->actingAs($transporteur)
            ->postJson("/api/v1/trips/{$start['id']}/accept-course")
            ->assertOk()->json('trip');
        $this->assertEquals('CONFIRME', $accepted['statut']);

        // 4. Destination proposée → DESTINATION_PROPOSEE.
        $destResp = $this->postJson("/api/v1/trips/{$start['id']}/destination", [
            'destination_address' => 'Yaoundé Centre',
            'latitude' => 3.8700,
            'longitude' => 11.5210,
        ])->assertOk();
        $dest = $destResp->json('trip');
        $this->assertEquals('DESTINATION_PROPOSEE', $dest['statut']);

        // 4b. Au CHOIX de la destination, le QR scanné RESTE valide et
        // actif : pas de rotation tant que le trajet n'a pas démarré.
        $this->assertFalse($destResp->json('qr_rotation.rotated'));
        $this->assertEquals('attente_demarrage', $destResp->json('qr_rotation.reason'));
        $this->assertDatabaseHas('qr_codes', [
            'token' => $vehicle['qr_codes'][0]['token'],
            'actif' => true,
        ]);

        // 5. Destination confirmée → EN_COURS.
        $ongoingResp = $this->postJson("/api/v1/trips/{$start['id']}/confirm-destination", [
            'confirmed' => true,
        ])->assertOk();
        $ongoing = $ongoingResp->json('trip');
        $this->assertEquals('EN_COURS', $ongoing['statut']);

        // 5b. Au DÉMARRAGE réel, le QR scanné est désactivé et un QR frais
        // attend les prochains passagers.
        $this->assertTrue($ongoingResp->json('qr_rotation.rotated'));
        $this->assertEquals('trajet_demarre', $ongoingResp->json('qr_rotation.reason'));
        $this->assertDatabaseHas('qr_codes', [
            'token' => $vehicle['qr_codes'][0]['token'],
            'actif' => false,
        ]);
        $freshQr = QrCode::where('vehicle_id', $vehicle['id'])
            ->where('actif', true)
            ->first();
        $this->assertNotNull($freshQr);
        $this->assertNotEquals($vehicle['qr_codes'][0]['token'], $freshQr->token);

        // 6. Positions GPS pendant le trajet.
        $this->postJson("/api/v1/trips/{$start['id']}/locations", [
            'latitude' => 3.8520,
            'longitude' => 11.5050,
            'vitesse_km_h' => 40,
            'captured_at' => now()->toIso8601String(),
        ])->assertCreated();

        $this->postJson("/api/v1/trips/{$start['id']}/locations", [
            'latitude' => 3.8600,
            'longitude' => 11.5100,
            'vitesse_km_h' => 45,
            'captured_at' => now()->toIso8601String(),
        ])->assertCreated();

        // 7. Itinéraire décodé disponible pour la carte.
        $route = $this->getJson("/api/v1/trips/{$start['id']}/route")->assertOk()->json();
        $this->assertNotEmpty($route['points']);
        $this->assertArrayHasKey('destination', $route);

        // 8. Fin à double confirmation : le passager propose…
        $firstEnd = $this->actingAs($passager)->postJson("/api/v1/trips/{$start['id']}/end")
            ->assertOk();
        $this->assertEquals('FIN_EN_ATTENTE', $firstEnd->json('trip.statut'));
        $this->assertEquals('waiting_other', $firstEnd->json('end_request'));

        // …puis le transporteur confirme → TERMINE avec distance calculée.
        $ended = $this->actingAs($transporteur)->postJson("/api/v1/trips/{$start['id']}/end")
            ->assertOk()->json('trip');
        $this->assertEquals('TERMINE', $ended['statut']);
        $this->assertNotNull($ended['distance_km']);
        $this->assertGreaterThan(0, (float) $ended['distance_km']);

        // 9. L'historique du passager contient le trajet.
        $history = $this->getJson('/api/v1/trips/history')->assertOk()->json();
        $this->assertNotEmpty($history);
    }

    public function test_scan_replaces_stale_scanne_trip(): void
    {
        Http::fake(['*' => Http::response('', 500)]);
        config(['services.ai.enabled' => false]);

        $transporteur = $this->user('transporteur@example.com', '690000010', 'transporteur');
        $passager = $this->user('passager@example.com', '690000011', 'passager');

        $vehicle = $this->actingAs($transporteur)->postJson('/api/v1/vehicles', [
            'marque' => 'Toyota',
            'modele' => 'Corolla',
            'immatriculation' => 'LT-778-AB',
            'type' => 'VOITURE',
        ])->assertCreated()->json('vehicle');

        $this->actingAs($transporteur)->postJson("/api/v1/vehicles/{$vehicle['id']}/position", [
            'latitude' => 3.8480,
            'longitude' => 11.5021,
        ])->assertOk();

        // Premier scan OK → SCANNE.
        $first = $this->actingAs($passager)->postJson('/api/v1/trips/start', [
            'token' => $vehicle['qr_codes'][0]['token'],
            'latitude' => 3.8480,
            'longitude' => 11.5021,
        ])->assertCreated()->json('trip');

        $this->assertEquals('SCANNE', $first['statut']);

        // Deuxième scan : le SCANNE est un état de configuration, pas un vrai
        // trajet. Il est annulé automatiquement et le nouveau scan crée un
        // trajet frais. Le QR est multi-usage (24h) : c'est le MÊME token
        // qui reste actif et réutilisable.
        $newToken = QrCode::where('vehicle_id', $vehicle['id'])
            ->where('actif', true)
            ->value('token');
        $this->assertNotNull($newToken);

        $second = $this->actingAs($passager)->postJson('/api/v1/trips/start', [
            'token' => $newToken,
            'latitude' => 3.8480,
            'longitude' => 11.5021,
        ])->assertCreated()->json('trip');

        // Nouveau trajet créé.
        $this->assertNotEquals($first['id'], $second['id']);
        $this->assertEquals('SCANNE', $second['statut']);

        // L'ancien trajet est annulé.
        $this->assertDatabaseHas('trips', [
            'id' => $first['id'],
            'statut' => 'ANNULE',
        ]);

        // Le QR est multi-usage : il RESTE actif après les scans
        // (validité 24h, réutilisable pour d'autres trajets).
        $this->assertDatabaseHas('qr_codes', [
            'token' => $vehicle['qr_codes'][0]['token'],
            'actif' => true,
        ]);

        // Un nouveau QR régénéré est actif.
        $this->assertEquals(1, QrCode::where('vehicle_id', $vehicle['id'])
            ->where('actif', true)
            ->count());
    }

    public function test_scan_is_rejected_while_trip_is_confirmed(): void
    {
        Http::fake(['*' => Http::response('', 500)]);
        config(['services.ai.enabled' => false]);

        $transporteur = $this->user('transporteur@example.com', '690000010', 'transporteur');
        $passager = $this->user('passager@example.com', '690000011', 'passager');

        $vehicle = $this->actingAs($transporteur)->postJson('/api/v1/vehicles', [
            'marque' => 'Toyota',
            'modele' => 'Corolla',
            'immatriculation' => 'LT-778-AB',
            'type' => 'VOITURE',
        ])->assertCreated()->json('vehicle');

        $this->actingAs($transporteur)->postJson("/api/v1/vehicles/{$vehicle['id']}/position", [
            'latitude' => 3.8480,
            'longitude' => 11.5021,
        ])->assertOk();

        // Scan → SCANNE → confirm-embarquement → EN_ATTENTE → accept-course → CONFIRME.
        $trip = $this->actingAs($passager)->postJson('/api/v1/trips/start', [
            'token' => $vehicle['qr_codes'][0]['token'],
            'latitude' => 3.8480,
            'longitude' => 11.5021,
        ])->assertCreated()->json('trip');

        $this->postJson("/api/v1/trips/{$trip['id']}/confirm-embarquement")->assertOk();
        $this->actingAs($transporteur)
            ->postJson("/api/v1/trips/{$trip['id']}/accept-course")
            ->assertOk();

        // Nouveau scan interdit : un trajet CONFIRME est un vrai trajet en
        // cours, à terminer avant d'en lancer un autre (reprise auto).
        $newToken = QrCode::where('vehicle_id', $vehicle['id'])
            ->where('actif', true)
            ->value('token');

        $second = $this->actingAs($passager)->postJson('/api/v1/trips/start', [
            'token' => $newToken,
            'latitude' => 3.8480,
            'longitude' => 11.5021,
        ]);

        $second->assertStatus(422);
        $this->assertTrue($second->json('active_trip'));
        $this->assertEquals($trip['id'], $second->json('trip.id'));
    }

    public function test_current_returns_trip_in_any_active_status(): void
    {
        Http::fake(['*' => Http::response('', 500)]);
        config(['services.ai.enabled' => false]);

        $transporteur = $this->user('transporteur@example.com', '690000010', 'transporteur');
        $passager = $this->user('passager@example.com', '690000011', 'passager');

        $vehicle = $this->actingAs($transporteur)->postJson('/api/v1/vehicles', [
            'marque' => 'Toyota',
            'modele' => 'Corolla',
            'immatriculation' => 'LT-779-AB',
            'type' => 'VOITURE',
        ])->assertCreated()->json('vehicle');

        $this->actingAs($transporteur)->postJson("/api/v1/vehicles/{$vehicle['id']}/position", [
            'latitude' => 3.8480,
            'longitude' => 11.5021,
        ])->assertOk();

        $start = $this->actingAs($passager)->postJson('/api/v1/trips/start', [
            'token' => $vehicle['qr_codes'][0]['token'],
            'latitude' => 3.8480,
            'longitude' => 11.5021,
        ])->assertCreated()->json('trip');

        // Statut SCANNE : le passager rouvre l'app → il retrouve son trajet.
        $current = $this->getJson('/api/v1/trips/current')->assertOk()->json('trip');
        $this->assertNotNull($current);
        $this->assertEquals($start['id'], $current['id']);
        $this->assertEquals('SCANNE', $current['statut']);
    }

    public function test_transporteur_can_accept_up_to_seven_courses(): void
    {
        Http::fake(['*' => Http::response('', 500)]);
        config(['services.ai.enabled' => false]);

        $transporteur = $this->user('transporteur@example.com', '690000010', 'transporteur');
        $passager1 = $this->user('passager1@example.com', '690000011', 'passager');
        $passager2 = $this->user('passager2@example.com', '690000012', 'passager');

        $vehicle = $this->actingAs($transporteur)->postJson('/api/v1/vehicles', [
            'marque' => 'Toyota',
            'modele' => 'Corolla',
            'immatriculation' => 'LT-780-AB',
            'type' => 'VOITURE',
        ])->assertCreated()->json('vehicle');

        $this->actingAs($transporteur)->postJson("/api/v1/vehicles/{$vehicle['id']}/position", [
            'latitude' => 3.8480,
            'longitude' => 11.5021,
        ])->assertOk();

        // Course 1 : passager 1 scanne + confirme → EN_ATTENTE_TRANSPORTEUR.
        $trip1 = $this->actingAs($passager1)->postJson('/api/v1/trips/start', [
            'token' => $vehicle['qr_codes'][0]['token'],
            'latitude' => 3.8480,
            'longitude' => 11.5021,
        ])->assertCreated()->json('trip');
        $this->postJson("/api/v1/trips/{$trip1['id']}/confirm-embarquement")->assertOk();

        // Le transporteur accepte la course 1 → CONFIRME.
        $this->actingAs($transporteur)
            ->postJson("/api/v1/trips/{$trip1['id']}/accept-course")
            ->assertOk();

        // Course 2 : le second passager passe par un second véhicule.
        $transporteur2 = $this->user('transporteur2@example.com', '690000013', 'transporteur');
        $vehicle2 = $this->actingAs($transporteur2)->postJson('/api/v1/vehicles', [
            'marque' => 'Honda',
            'modele' => 'Civic',
            'immatriculation' => 'LT-781-CD',
            'type' => 'VOITURE',
        ])->assertCreated()->json('vehicle');
        $this->actingAs($transporteur2)->postJson("/api/v1/vehicles/{$vehicle2['id']}/position", [
            'latitude' => 3.8480,
            'longitude' => 11.5021,
        ])->assertOk();

        $trip2 = $this->actingAs($passager2)->postJson('/api/v1/trips/start', [
            'token' => $vehicle2['qr_codes'][0]['token'],
            'latitude' => 3.8480,
            'longitude' => 11.5021,
        ])->assertCreated()->json('trip');
        $this->actingAs($passager2)->postJson("/api/v1/trips/{$trip2['id']}/confirm-embarquement")->assertOk();

        // transporteur2 est libre : il accepte la course 2 → CONFIRME.
        $ok = $this->actingAs($transporteur2)
            ->postJson("/api/v1/trips/{$trip2['id']}/accept-course")
            ->assertOk();
        $this->assertEquals('CONFIRME', $ok->json('trip.statut'));

        // Un troisième passager propose une course au transporteur2 qui n'a
        // qu'une course active : accepté (multi-courses autorisées).
        $passager3 = $this->user('passager3@example.com', '690000014', 'passager');
        $trip3 = Trip::create([
            'passager_id' => $passager3->id,
            'transporteur_id' => $transporteur2->id,
            'vehicle_id' => $vehicle2['id'],
            'qr_token' => 'tok-test-3',
            'start_latitude' => 3.8480,
            'start_longitude' => 11.5021,
            'started_at' => now(),
            'statut' => 'EN_ATTENTE_TRANSPORTEUR',
        ]);

        $this->actingAs($transporteur2)
            ->postJson("/api/v1/trips/{$trip3->id}/accept-course")
            ->assertOk();

        // On monte à 7 courses actives : la 8e est refusée (422).
        for ($i = 0; $i < 5; $i++) {
            Trip::create([
                'passager_id' => $passager3->id,
                'transporteur_id' => $transporteur2->id,
                'vehicle_id' => $vehicle2['id'],
                'qr_token' => 'tok-test-bulk-' . $i,
                'start_latitude' => 3.8480,
                'start_longitude' => 11.5021,
                'started_at' => now()->subMinutes(10 + $i),
                'statut' => 'EN_COURS',
            ]);
        }
        $trip8 = Trip::create([
            'passager_id' => $passager3->id,
            'transporteur_id' => $transporteur2->id,
            'vehicle_id' => $vehicle2['id'],
            'qr_token' => 'tok-test-8',
            'start_latitude' => 3.8480,
            'start_longitude' => 11.5021,
            'started_at' => now(),
            'statut' => 'EN_ATTENTE_TRANSPORTEUR',
        ]);

        $refused = $this->actingAs($transporteur2)
            ->postJson("/api/v1/trips/{$trip8->id}/accept-course");
        $this->assertEquals(422, $refused->status());
    }

    public function test_passenger_can_cancel_waiting_course_and_rescan(): void
    {
        Http::fake(['*' => Http::response('', 500)]);
        config(['services.ai.enabled' => false]);

        $transporteur = $this->user('transporteur@example.com', '690000010', 'transporteur');
        $passager = $this->user('passager@example.com', '690000011', 'passager');

        $vehicle = $this->actingAs($transporteur)->postJson('/api/v1/vehicles', [
            'marque' => 'Toyota',
            'modele' => 'Corolla',
            'immatriculation' => 'LT-783-AB',
            'type' => 'VOITURE',
        ])->assertCreated()->json('vehicle');

        $this->actingAs($transporteur)->postJson("/api/v1/vehicles/{$vehicle['id']}/position", [
            'latitude' => 3.8480,
            'longitude' => 11.5021,
        ])->assertOk();

        // 1. Scan → SCANNE, puis confirmation → EN_ATTENTE_TRANSPORTEUR.
        $trip = $this->actingAs($passager)->postJson('/api/v1/trips/start', [
            'token' => $vehicle['qr_codes'][0]['token'],
            'latitude' => 3.8480,
            'longitude' => 11.5021,
        ])->assertCreated()->json('trip');

        $this->postJson("/api/v1/trips/{$trip['id']}/confirm-embarquement")->assertOk();

        // 2. Le passager annule → ANNULE + notification au transporteur.
        $cancel = $this->postJson("/api/v1/trips/{$trip['id']}/cancel")->assertOk();
        $this->assertEquals('ANNULE', $cancel->json('trip.statut'));
        $this->assertEquals('ANNULATION_PASSAGER', $cancel->json('trip.end_method'));
        $this->assertDatabaseHas('notifications', [
            'user_id' => $transporteur->id,
            'titre' => 'Demande de course annulée',
        ]);

        // 3. Il peut immédiatement scanner un autre véhicule (guard libéré).
        $transporteur2 = $this->user('transporteur2@example.com', '690000012', 'transporteur');
        $vehicle2 = $this->actingAs($transporteur2)->postJson('/api/v1/vehicles', [
            'marque' => 'Honda',
            'modele' => 'Civic',
            'immatriculation' => 'LT-784-CD',
            'type' => 'VOITURE',
        ])->assertCreated()->json('vehicle');

        $this->actingAs($transporteur2)->postJson("/api/v1/vehicles/{$vehicle2['id']}/position", [
            'latitude' => 3.8480,
            'longitude' => 11.5021,
        ])->assertOk();

        $rescan = $this->actingAs($passager)->postJson('/api/v1/trips/start', [
            'token' => $vehicle2['qr_codes'][0]['token'],
            'latitude' => 3.8480,
            'longitude' => 11.5021,
        ])->assertCreated();

        $this->assertEquals('SCANNE', $rescan->json('trip.statut'));
    }

    public function test_cancel_is_rejected_after_course_confirmed(): void
    {
        Http::fake(['*' => Http::response('', 500)]);
        config(['services.ai.enabled' => false]);

        $transporteur = $this->user('transporteur@example.com', '690000010', 'transporteur');
        $passager = $this->user('passager@example.com', '690000011', 'passager');

        $vehicle = $this->actingAs($transporteur)->postJson('/api/v1/vehicles', [
            'marque' => 'Toyota',
            'modele' => 'Corolla',
            'immatriculation' => 'LT-785-AB',
            'type' => 'VOITURE',
        ])->assertCreated()->json('vehicle');

        $this->actingAs($transporteur)->postJson("/api/v1/vehicles/{$vehicle['id']}/position", [
            'latitude' => 3.8480,
            'longitude' => 11.5021,
        ])->assertOk();

        $trip = $this->actingAs($passager)->postJson('/api/v1/trips/start', [
            'token' => $vehicle['qr_codes'][0]['token'],
            'latitude' => 3.8480,
            'longitude' => 11.5021,
        ])->assertCreated()->json('trip');

        $this->postJson("/api/v1/trips/{$trip['id']}/confirm-embarquement")->assertOk();
        $this->actingAs($transporteur)
            ->postJson("/api/v1/trips/{$trip['id']}/accept-course")
            ->assertOk();

        // CONFIRME : la course est engagée, l'annulation passager est refusée
        // (il faut passer par la fin de trajet normale).
        $refused = $this->actingAs($passager)
            ->postJson("/api/v1/trips/{$trip['id']}/cancel");
        $refused->assertNotFound();
    }

    public function test_scan_auto_closes_abandoned_active_trip(): void
    {
        Http::fake(['*' => Http::response('', 500)]);
        config(['services.ai.enabled' => false]);

        $transporteur = $this->user('transporteur@example.com', '690000010', 'transporteur');
        $passager = $this->user('passager@example.com', '690000011', 'passager');

        $vehicle = $this->actingAs($transporteur)->postJson('/api/v1/vehicles', [
            'marque' => 'Toyota',
            'modele' => 'Corolla',
            'immatriculation' => 'LT-779-AB',
            'type' => 'VOITURE',
        ])->assertCreated()->json('vehicle');

        $this->actingAs($transporteur)->postJson("/api/v1/vehicles/{$vehicle['id']}/position", [
            'latitude' => 3.8480,
            'longitude' => 11.5021,
        ])->assertOk();

        // Trajet EN_COURS abandonné (ex. app fermée) sans update depuis 7h.
        $stale = Trip::create([
            'passager_id' => $passager->id,
            'transporteur_id' => $transporteur->id,
            'vehicle_id' => $vehicle['id'],
            'start_latitude' => 3.8480,
            'start_longitude' => 11.5021,
            'started_at' => now()->subHours(7),
            'statut' => 'EN_COURS',
        ]);
        Trip::where('id', $stale->id)->update(['updated_at' => now()->subHours(7)]);

        // Le scan ne doit PAS renvoyer 422 : le trajet abandonné est clôturé
        // automatiquement et le nouveau scan crée un trajet frais.
        $fresh = $this->actingAs($passager)->postJson('/api/v1/trips/start', [
            'token' => $vehicle['qr_codes'][0]['token'],
            'latitude' => 3.8480,
            'longitude' => 11.5021,
        ])->assertCreated()->json('trip');

        $this->assertEquals('SCANNE', $fresh['statut']);
        $this->assertDatabaseHas('trips', [
            'id' => $stale->id,
            'statut' => 'ANNULE',
            'end_method' => 'AUTO_PURGE',
        ]);
    }

    public function test_scan_is_rejected_while_trip_is_active(): void
    {
        Http::fake(['*' => Http::response('', 500)]);
        config(['services.ai.enabled' => false]);

        $transporteur = $this->user('transporteur@example.com', '690000010', 'transporteur');
        $passager = $this->user('passager@example.com', '690000011', 'passager');

        $vehicle = $this->actingAs($transporteur)->postJson('/api/v1/vehicles', [
            'marque' => 'Toyota',
            'modele' => 'Corolla',
            'immatriculation' => 'LT-780-AB',
            'type' => 'VOITURE',
        ])->assertCreated()->json('vehicle');

        $this->actingAs($transporteur)->postJson("/api/v1/vehicles/{$vehicle['id']}/position", [
            'latitude' => 3.8480,
            'longitude' => 11.5021,
        ])->assertOk();

        $scanPayload = [
            'token' => $vehicle['qr_codes'][0]['token'],
            'latitude' => 3.8480,
            'longitude' => 11.5021,
        ];

        // 1 trajet EN_COURS récent : impossible d'en lancer un second sans
        // terminer le premier (422 + reprise du trajet actif).
        $active = Trip::create([
            'passager_id' => $passager->id,
            'transporteur_id' => $transporteur->id,
            'vehicle_id' => $vehicle['id'],
            'start_latitude' => 3.8480,
            'start_longitude' => 11.5021,
            'started_at' => now()->subMinutes(30),
            'statut' => 'EN_COURS',
        ]);

        $refused = $this->actingAs($passager)->postJson('/api/v1/trips/start', $scanPayload);
        $refused->assertStatus(422);
        $this->assertTrue($refused->json('active_trip'));
        $this->assertEquals($active->id, $refused->json('trip.id'));

        // Le trajet actif n'est pas touché.
        $this->assertDatabaseHas('trips', [
            'id' => $active->id,
            'statut' => 'EN_COURS',
        ]);
    }

    public function test_history_scopes_en_cours_and_fini(): void
    {
        Http::fake(['*' => Http::response('', 500)]);
        config(['services.ai.enabled' => false]);

        $transporteur = $this->user('transporteur@example.com', '690000010', 'transporteur');
        $passager = $this->user('passager@example.com', '690000011', 'passager');

        $vehicle = $this->actingAs($transporteur)->postJson('/api/v1/vehicles', [
            'marque' => 'Toyota',
            'modele' => 'Corolla',
            'immatriculation' => 'LT-786-AB',
            'type' => 'VOITURE',
        ])->assertCreated()->json('vehicle');

        $ongoing = Trip::create([
            'passager_id' => $passager->id,
            'transporteur_id' => $transporteur->id,
            'vehicle_id' => $vehicle['id'],
            'start_latitude' => 3.8480,
            'start_longitude' => 11.5021,
            'started_at' => now()->subHour(),
            'statut' => 'EN_COURS',
        ]);
        $finished = Trip::create([
            'passager_id' => $passager->id,
            'transporteur_id' => $transporteur->id,
            'vehicle_id' => $vehicle['id'],
            'start_latitude' => 3.8480,
            'start_longitude' => 11.5021,
            'started_at' => now()->subHours(3),
            'ended_at' => now()->subHours(2),
            'statut' => 'TERMINE',
        ]);

        // Vue "en cours" : que le trajet actif.
        $enCours = $this->actingAs($transporteur)
            ->getJson('/api/v1/trips/history?scope=en_cours')
            ->assertOk()
            ->json('trips.data');
        $this->assertCount(1, $enCours);
        $this->assertEquals($ongoing->id, $enCours[0]['id']);

        // Vue "fini" (défaut) : que le trajet terminé.
        $fini = $this->actingAs($transporteur)
            ->getJson('/api/v1/trips/history')
            ->assertOk()
            ->json('trips.data');
        $this->assertCount(1, $fini);
        $this->assertEquals($finished->id, $fini[0]['id']);
    }

    public function test_stationary_drift_does_not_inflate_distance(): void
    {
        Http::fake(['*' => Http::response('', 500)]);
        config(['services.ai.enabled' => false]);

        $transporteur = $this->user('transporteur@example.com', '690000010', 'transporteur');
        $passager = $this->user('passager@example.com', '690000011', 'passager');

        $vehicle = $this->actingAs($transporteur)->postJson('/api/v1/vehicles', [
            'marque' => 'Toyota',
            'modele' => 'Corolla',
            'immatriculation' => 'LT-790-AB',
            'type' => 'VOITURE',
        ])->assertCreated()->json('vehicle');

        // Trajet EN_COURS immobile : 12 points GPS qui errent de ±5 m
        // (dérive capteur à l'arrêt), sans destination.
        $trip = Trip::create([
            'passager_id' => $passager->id,
            'transporteur_id' => $transporteur->id,
            'vehicle_id' => $vehicle['id'],
            'start_latitude' => 3.8480,
            'start_longitude' => 11.5021,
            'started_at' => now()->subMinutes(5),
            'statut' => 'EN_COURS',
        ]);

        $jitter = [
            [3.84801, 11.50211], [3.84799, 11.50209], [3.84802, 11.50212],
            [3.84798, 11.50208], [3.84800, 11.50210], [3.84801, 11.50209],
            [3.84799, 11.50212], [3.84802, 11.50208], [3.84800, 11.50211],
            [3.84801, 11.50210], [3.84798, 11.50211], [3.84802, 11.50209],
        ];
        foreach ($jitter as $i => [$lat, $lng]) {
            $this->actingAs($passager)->postJson("/api/v1/trips/{$trip->id}/locations", [
                'latitude' => $lat,
                'longitude' => $lng,
                'vitesse_km_h' => 0,
                'captured_at' => now()->subMinutes(5 - $i)->toIso8601String(),
            ])->assertCreated();
        }

        $firstEnd = $this->actingAs($passager)
            ->postJson("/api/v1/trips/{$trip->id}/end")
            ->assertOk();
        // 1er clic : demande enregistrée, trajet NON terminé.
        $this->assertEquals('FIN_EN_ATTENTE', $firstEnd->json('trip.statut'));
        $this->assertEquals('waiting_other', $firstEnd->json('end_request'));

        // 2e clic par l'autre partie : TERMINE.
        $ended = $this->actingAs($transporteur)
            ->postJson("/api/v1/trips/{$trip->id}/end")
            ->assertOk()
            ->json('trip');

        // Tous les segments < 10 m : distance quasi nulle (pas de km fantômes).
        $this->assertEquals('TERMINE', $ended['statut']);
        $this->assertLessThan(0.05, (float) $ended['distance_km']);
    }

    public function test_end_requires_both_sides_to_confirm(): void
    {
        Http::fake(['*' => Http::response('', 500)]);
        config(['services.ai.enabled' => false]);

        $transporteur = $this->user('transporteur@example.com', '690000010', 'transporteur');
        $passager = $this->user('passager@example.com', '690000011', 'passager');

        $vehicle = $this->actingAs($transporteur)->postJson('/api/v1/vehicles', [
            'marque' => 'Toyota',
            'modele' => 'Corolla',
            'immatriculation' => 'LT-791-AB',
            'type' => 'VOITURE',
        ])->assertCreated()->json('vehicle');

        $trip = Trip::create([
            'passager_id' => $passager->id,
            'transporteur_id' => $transporteur->id,
            'vehicle_id' => $vehicle['id'],
            'start_latitude' => 3.8480,
            'start_longitude' => 11.5021,
            'started_at' => now()->subMinutes(20),
            'statut' => 'EN_COURS',
        ]);

        // 1er clic (passager) : FIN_EN_ATTENTE + notif au transporteur.
        $first = $this->actingAs($passager)
            ->postJson("/api/v1/trips/{$trip->id}/end")
            ->assertOk();
        $this->assertEquals('FIN_EN_ATTENTE', $first->json('trip.statut'));
        $this->assertEquals('passager', $first->json('trip.fin_demandee_par'));
        $this->assertEquals('waiting_other', $first->json('end_request'));
        $this->assertDatabaseHas('notifications', [
            'user_id' => $transporteur->id,
            'titre' => 'Fin de course à confirmer',
        ]);

        // 2e clic par la MÊME partie : idempotent, toujours en attente.
        $again = $this->actingAs($passager)
            ->postJson("/api/v1/trips/{$trip->id}/end")
            ->assertOk();
        $this->assertEquals('FIN_EN_ATTENTE', $again->json('trip.statut'));

        // Clic par l'AUTRE partie : TERMINE.
        $done = $this->actingAs($transporteur)
            ->postJson("/api/v1/trips/{$trip->id}/end")
            ->assertOk()
            ->json('trip');
        $this->assertEquals('TERMINE', $done['statut']);
        $this->assertEquals('MANUEL', $done['end_method']);
    }

    public function test_unconfirmed_end_auto_closes_after_24h(): void
    {
        Http::fake(['*' => Http::response('', 500)]);
        config(['services.ai.enabled' => false]);

        $transporteur = $this->user('transporteur@example.com', '690000010', 'transporteur');
        $passager = $this->user('passager@example.com', '690000011', 'passager');

        $vehicle = $this->actingAs($transporteur)->postJson('/api/v1/vehicles', [
            'marque' => 'Toyota',
            'modele' => 'Corolla',
            'immatriculation' => 'LT-792-AB',
            'type' => 'VOITURE',
        ])->assertCreated()->json('vehicle');

        $trip = Trip::create([
            'passager_id' => $passager->id,
            'transporteur_id' => $transporteur->id,
            'vehicle_id' => $vehicle['id'],
            'start_latitude' => 3.8480,
            'start_longitude' => 11.5021,
            'started_at' => now()->subHours(26),
            'statut' => 'EN_COURS',
        ]);

        // Demande du passager, puis voyage temporel : +25h sans réponse.
        $this->actingAs($passager)->postJson("/api/v1/trips/{$trip->id}/end")->assertOk();
        Trip::where('id', $trip->id)->update(['fin_demandee_at' => now()->subHours(25)]);

        // Le poll status() déclenche la clôture auto paresseuse.
        $status = $this->actingAs($passager)
            ->getJson("/api/v1/trips/{$trip->id}/status")
            ->assertOk()
            ->json('trip');
        $this->assertEquals('TERMINE', $status['statut']);
        $this->assertEquals('AUTO_24H', $status['end_method']);
    }

    public function test_fin_en_attente_counts_as_active_trip(): void
    {
        Http::fake(['*' => Http::response('', 500)]);
        config(['services.ai.enabled' => false]);

        $transporteur = $this->user('transporteur@example.com', '690000010', 'transporteur');
        $passager = $this->user('passager@example.com', '690000011', 'passager');

        $vehicle = $this->actingAs($transporteur)->postJson('/api/v1/vehicles', [
            'marque' => 'Toyota',
            'modele' => 'Corolla',
            'immatriculation' => 'LT-793-AB',
            'type' => 'VOITURE',
        ])->assertCreated()->json('vehicle');

        $this->actingAs($transporteur)->postJson("/api/v1/vehicles/{$vehicle['id']}/position", [
            'latitude' => 3.8480,
            'longitude' => 11.5021,
        ])->assertOk();

        Trip::create([
            'passager_id' => $passager->id,
            'transporteur_id' => $transporteur->id,
            'vehicle_id' => $vehicle['id'],
            'start_latitude' => 3.8480,
            'start_longitude' => 11.5021,
            'started_at' => now()->subMinutes(30),
            'statut' => 'FIN_EN_ATTENTE',
            'fin_demandee_par' => 'passager',
            'fin_demandee_at' => now()->subMinutes(5),
        ]);

        // Un trajet en attente de co-confirmation bloque toujours un scan.
        $this->actingAs($passager)->postJson('/api/v1/trips/start', [
            'token' => $vehicle['qr_codes'][0]['token'],
            'latitude' => 3.8480,
            'longitude' => 11.5021,
        ])->assertStatus(422);
    }
}