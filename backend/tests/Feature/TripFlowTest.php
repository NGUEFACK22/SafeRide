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
        $start = $this->actingAs($passager)->postJson('/api/v1/trips/start', [
            'token' => $vehicle['qr_codes'][0]['token'],
            'latitude' => 3.8480,
            'longitude' => 11.5021,
        ])->assertCreated()->json('trip');

        $this->assertEquals('SCANNE', $start['statut']);

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
        $dest = $this->postJson("/api/v1/trips/{$start['id']}/destination", [
            'destination_address' => 'Yaoundé Centre',
            'latitude' => 3.8700,
            'longitude' => 11.5210,
        ])->assertOk()->json('trip');
        $this->assertEquals('DESTINATION_PROPOSEE', $dest['statut']);

        // 5. Destination confirmée → EN_COURS.
        $ongoing = $this->postJson("/api/v1/trips/{$start['id']}/confirm-destination", [
            'confirmed' => true,
        ])->assertOk()->json('trip');
        $this->assertEquals('EN_COURS', $ongoing['statut']);

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

        // 8. Fin du trajet → TERMINE avec distance calculée.
        $ended = $this->postJson("/api/v1/trips/{$start['id']}/end")
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
        // trajet frais (QR régénéré consommé → le transporteur voit un QR
        // nouveau sur son écran).
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

        // Le QR consommé est désactivé.
        $this->assertDatabaseHas('qr_codes', [
            'token' => $vehicle['qr_codes'][0]['token'],
            'actif' => false,
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

        // Nouveau scan interdit : le trajet est CONFIRME (vrai trajet en cours).
        $newToken = QrCode::where('vehicle_id', $vehicle['id'])
            ->where('actif', true)
            ->value('token');

        $second = $this->actingAs($passager)->postJson('/api/v1/trips/start', [
            'token' => $newToken,
            'latitude' => 3.8480,
            'longitude' => 11.5021,
        ]);

        $this->assertEquals(422, $second->status());
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

    public function test_transporteur_cannot_accept_two_courses(): void
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

        // Un troisième passager propose une course au transporteur2 (occupé) :
        // refus 422 car il a déjà une course active.
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

        $refused = $this->actingAs($transporteur2)
            ->postJson("/api/v1/trips/{$trip3->id}/accept-course");
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
}