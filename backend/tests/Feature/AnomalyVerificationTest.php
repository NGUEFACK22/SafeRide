<?php

namespace Tests\Feature;

use App\Http\Controllers\AnomalyVerificationController;
use App\Models\AnomalyVerification;
use App\Models\Role;
use App\Models\SosAlert;
use App\Models\Trip;
use App\Models\User;
use App\Services\RouteService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class AnomalyVerificationTest extends TestCase
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
        $this->verifyIdentity($user);

        return $user;
    }

    /**
     * Reproduit le cycle complet jusqu'à EN_COURS (comme TripFlowTest) et
     * renvoie le trajet avec un planned_route_polyline en ligne droite.
     */
    private function ongoingTrip(): array
    {
        Http::fake(['*' => Http::response('', 500)]);

        $transporteur = $this->user('transporteur@example.com', '690000010', 'transporteur');
        $passager = $this->user('passager@example.com', '690000011', 'passager');

        $vehicle = $this->actingAs($transporteur)->postJson('/api/v1/vehicles', [
            'marque' => 'Toyota',
            'modele' => 'Corolla',
            'immatriculation' => 'LT-777-AB',
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

        $this->postJson("/api/v1/trips/{$start['id']}/confirm-embarquement")->assertOk();

        $this->actingAs($transporteur)
            ->postJson("/api/v1/trips/{$start['id']}/accept-course")
            ->assertOk();

        $this->postJson("/api/v1/trips/{$start['id']}/destination", [
            'destination_address' => 'Akwa, Douala',
            'latitude' => 3.8700,
            'longitude' => 11.5210,
        ])->assertOk();

        $this->postJson("/api/v1/trips/{$start['id']}/confirm-destination", [
            'confirmed' => true,
        ])->assertOk();

        $trip = Trip::findOrFail($start['id']);
        $this->assertEquals('EN_COURS', $trip->statut);

        return [$trip, $passager, $transporteur];
    }

    public function test_route_deviation_notifies_passenger_after_persistence(): void
    {
        [$trip, $passager, $transporteur] = $this->ongoingTrip();

        // Tracé prévu : ligne droite courte (start → destination).
        $routeService = app(RouteService::class);
        $trip->planned_route_polyline = $routeService->encodePolyline([
            [3.8480, 11.5021],
            [3.8700, 11.5210],
        ]);
        $trip->save();

        // Écart immédiat seul : PAS de notification (le transporteur peut
        // revenir sur l'itinéraire dans le délai de 5 min).
        $this->actingAs($passager)->postJson("/api/v1/trips/{$trip->id}/locations", [
            'latitude' => 4.2000,
            'longitude' => 12.0000,
            'vitesse_km_h' => 40,
            'captured_at' => now()->toIso8601String(),
        ])->assertCreated();
        $this->assertDatabaseCount('anomaly_verifications', 0);

        // Point hors tracé vieilli de 6 min : la déviation PERSISTE (> 5 min)
        // => le passager est notifié (le transporteur n'est pas revenu sur
        // l'itinéraire).
        $this->actingAs($passager)->postJson("/api/v1/trips/{$trip->id}/locations", [
            'latitude' => 4.2000,
            'longitude' => 12.0000,
            'vitesse_km_h' => 40,
            'captured_at' => now()->subMinutes(6)->toIso8601String(),
        ])->assertCreated();
        $this->actingAs($passager)->postJson("/api/v1/trips/{$trip->id}/locations", [
            'latitude' => 4.2000,
            'longitude' => 12.0000,
            'vitesse_km_h' => 40,
            'captured_at' => now()->toIso8601String(),
        ])->assertCreated();

        // Une seule vérification DETOUR : celle du PASSAGER (c'est lui qu'on
        // interroge sur le non-respect de l'itinéraire).
        $this->assertDatabaseCount('anomaly_verifications', 1);
        $this->assertDatabaseHas('anomaly_verifications', [
            'trip_id' => $trip->id,
            'user_id' => $passager->id,
            'anomaly_type' => 'DETOUR',
            'statut' => 'EN_ATTENTE',
        ]);

        // Notification push envoyée au passager.
        $this->assertDatabaseHas('notifications', [
            'user_id' => $passager->id,
            'type' => 'ANOMALIE_VERIFICATION',
        ]);
    }

    public function test_prolonged_stop_notifies_passenger(): void
    {
        [$trip, $passager, $transporteur] = $this->ongoingTrip();

        // 5 positions à vitesse quasi nulle (< 2 km/h) étalées sur 11 min :
        // l'arrêt dure ≥ 10 min => le passager est interrogé (« tout va
        // bien ? »), pas le transporteur. Les 4 anciennes sont créées en base
        // (sans passer par POST /locations, qui déclencherait une fausse
        // perte de signal), la dernière fraîche via l'API.
        foreach ([11, 9, 7, 5] as $ago) {
            $trip->locations()->create([
                'latitude' => 3.8480,
                'longitude' => 11.5021,
                'vitesse_km_h' => 0,
                'captured_at' => now()->subMinutes($ago),
            ]);
        }
        $this->actingAs($passager)->postJson("/api/v1/trips/{$trip->id}/locations", [
            'latitude' => 3.8480,
            'longitude' => 11.5021,
            'vitesse_km_h' => 0,
            'captured_at' => now()->toIso8601String(),
        ])->assertCreated();

        $this->assertDatabaseCount('anomaly_verifications', 1);
        $this->assertDatabaseHas('anomaly_verifications', [
            'trip_id' => $trip->id,
            'user_id' => $passager->id,
            'anomaly_type' => 'STOP',
            'statut' => 'EN_ATTENTE',
        ]);
    }

    public function test_five_min_timeout_triggers_sos_on_unresponded_party(): void
    {
        [$trip, $passager, $transporteur] = $this->ongoingTrip();

        // Vérification du transporteur créée il y a 6 min, jamais répondue
        // (timeout de réponse : 5 min). SPEED : pas d'escalade bien-être.
        $verif = new AnomalyVerification;
        $verif->trip_id = $trip->id;
        $verif->user_id = $transporteur->id;
        $verif->anomaly_type = 'SPEED';
        $verif->description = 'Vitesse excessive non confirmée.';
        $verif->gravite = 'ELEVEE';
        $verif->statut = 'EN_ATTENTE';
        $verif->created_at = now()->subMinutes(6);
        $verif->save();

        $count = AnomalyVerificationController::processTimeouts();

        $this->assertSame(1, $count);

        // SOS lancé SUR le transporteur (celui qui n'a pas répondu).
        $this->assertDatabaseHas('sos_alerts', [
            'trip_id' => $trip->id,
            'passager_id' => $transporteur->id,
            'statut' => 'DECLENCHE',
        ]);

        // La vérification est clôturée → pas de SOS en double à la même minute.
        $this->assertDatabaseHas('anomaly_verifications', [
            'id' => AnomalyVerification::where('user_id', $transporteur->id)->value('id'),
            'statut' => 'ALARME',
        ]);

        $this->assertSame(0, AnomalyVerificationController::processTimeouts());
    }

    /** Détour EN_ATTENTE depuis $minutes, sans réponse, pour l'escalade. */
    private function wellbeingDetour(Trip $trip, User $passager, int $minutes): AnomalyVerification
    {
        $verif = AnomalyVerification::create([
            'trip_id' => $trip->id,
            'user_id' => $passager->id,
            'anomaly_type' => 'DETOUR',
            'description' => 'Déviation d\'itinéraire constante.',
            'gravite' => 'ELEVEE',
            'statut' => 'EN_ATTENTE',
        ]);
        // created_at est géré par les timestamps : on force l'ancienneté.
        $verif->created_at = now()->subMinutes($minutes);
        $verif->save();

        return $verif;
    }

    public function test_detour_no_rappel_before_10_min(): void
    {
        [$trip, $passager] = $this->ongoingTrip();
        $verif = $this->wellbeingDetour($trip, $passager, 6);

        $count = AnomalyVerificationController::processTimeouts();

        // Entre 5 et 10 min sans réponse : ni SOS, ni rappel.
        $this->assertSame(0, $count);
        $this->assertSame('EN_ATTENTE', $verif->fresh()->statut);
        $this->assertNull($verif->fresh()->rappel_at);
    }

    public function test_detour_rappel_after_10_min_and_sos_after_20(): void
    {
        [$trip, $passager] = $this->ongoingTrip();

        // Tracé prévu + position GPS hors tracé => la situation « n'est pas
        // réglée », l'escalade peut jouer.
        $routeService = app(RouteService::class);
        $trip->planned_route_polyline = $routeService->encodePolyline([
            [3.8480, 11.5021],
            [3.8700, 11.5210],
        ]);
        $trip->save();
        $trip->locations()->create([
            'latitude' => 4.2000,
            'longitude' => 12.0000,
            'vitesse_km_h' => 40,
            'captured_at' => now(),
        ]);

        $verif = $this->wellbeingDetour($trip, $passager, 11);

        // 11 min sans réponse -> 2e notification (rappel), PAS de SOS.
        $this->assertSame(0, AnomalyVerificationController::processTimeouts());
        $verif->refresh();
        $this->assertSame('EN_ATTENTE', $verif->statut);
        $this->assertNotNull($verif->rappel_at);
        $this->assertDatabaseHas('notifications', [
            'user_id' => $passager->id,
            'type' => 'ANOMALIE_VERIFICATION',
        ]);

        // Rappel il y a 5 min : on attend encore les 10 min du 2e délai.
        $verif->update(['rappel_at' => now()->subMinutes(5)]);
        $this->assertSame(0, AnomalyVerificationController::processTimeouts());
        $this->assertDatabaseCount('sos_alerts', 0);

        // Rappel depuis 11 min + toujours muet => SOS automatique.
        $verif->update(['rappel_at' => now()->subMinutes(11)]);
        $this->assertSame(1, AnomalyVerificationController::processTimeouts());
        $this->assertDatabaseHas('sos_alerts', [
            'trip_id' => $trip->id,
            'passager_id' => $passager->id,
            'statut' => 'DECLENCHE',
        ]);
        $this->assertSame('ALARME', $verif->fresh()->statut);
    }

    public function test_detour_clot_sans_sos_si_itineraire_retrouve(): void
    {
        [$trip, $passager] = $this->ongoingTrip();

        $routeService = app(RouteService::class);
        $trip->planned_route_polyline = $routeService->encodePolyline([
            [3.8480, 11.5021],
            [3.8700, 11.5210],
        ]);
        $trip->save();
        // Le véhicule est REVENU près du tracé (à ~100 m d'un sommet de la
        // polyline) : la situation est réglée.
        $trip->locations()->create([
            'latitude' => 3.8485,
            'longitude' => 11.5025,
            'vitesse_km_h' => 45,
            'captured_at' => now(),
        ]);

        $verif = $this->wellbeingDetour($trip, $passager, 11);

        $this->assertSame(0, AnomalyVerificationController::processTimeouts());
        $this->assertSame('CONFIRMEE', $verif->fresh()->statut);
        $this->assertDatabaseCount('sos_alerts', 0);
    }

    public function test_respond_normal_is_independent_per_party(): void
    {
        [$trip, $passager, $transporteur] = $this->ongoingTrip();

        $passengerVerif = AnomalyVerification::create([
            'trip_id' => $trip->id,
            'user_id' => $passager->id,
            'anomaly_type' => 'DETOUR',
            'description' => 'Déviation.',
            'gravite' => 'ELEVEE',
            'statut' => 'EN_ATTENTE',
        ]);
        $transporteurVerif = AnomalyVerification::create([
            'trip_id' => $trip->id,
            'user_id' => $transporteur->id,
            'anomaly_type' => 'DETOUR',
            'description' => 'Déviation.',
            'gravite' => 'ELEVEE',
            'statut' => 'EN_ATTENTE',
        ]);

        // Le passager répond "normal" : SA vérification est clôturée…
        $this->actingAs($passager)
            ->postJson("/api/v1/anomaly-verifications/{$passengerVerif->id}/respond", [
                'response' => 'normal',
            ])->assertOk();

        // … mais celle du transporteur reste EN_ATTENTE (réponse indépendante).
        $this->assertDatabaseHas('anomaly_verifications', [
            'id' => $passengerVerif->id,
            'statut' => 'CONFIRMEE',
        ]);
        $this->assertDatabaseHas('anomaly_verifications', [
            'id' => $transporteurVerif->id,
            'statut' => 'EN_ATTENTE',
        ]);

        // Chaque partie ne voit que SES vérifications en attente.
        $this->actingAs($transporteur)
            ->getJson('/api/v1/anomaly-verifications')
            ->assertOk()
            ->assertJsonCount(1, 'verifications');
    }

    public function test_respond_abnormal_triggers_sos(): void
    {
        [$trip, $passager] = $this->ongoingTrip();

        $verif = AnomalyVerification::create([
            'trip_id' => $trip->id,
            'user_id' => $passager->id,
            'anomaly_type' => 'STOP',
            'description' => 'Arrêt prolongé.',
            'gravite' => 'MOYENNE',
            'statut' => 'EN_ATTENTE',
        ]);

        $this->actingAs($passager)
            ->postJson("/api/v1/anomaly-verifications/{$verif->id}/respond", [
                'response' => 'abnormal',
            ])->assertOk();

        $this->assertDatabaseHas('anomaly_verifications', [
            'id' => $verif->id,
            'statut' => 'ALARME',
        ]);
        $this->assertDatabaseHas('sos_alerts', [
            'trip_id' => $trip->id,
            'passager_id' => $passager->id,
            'declenchement' => 'ANALYSE_IA',
        ]);
    }

    public function test_no_duplicate_verification_per_party(): void
    {
        [$trip, $passager, $transporteur] = $this->ongoingTrip();

        $routeService = app(RouteService::class);
        $trip->planned_route_polyline = $routeService->encodePolyline([
            [3.8480, 11.5021],
            [3.8700, 11.5210],
        ]);
        $trip->save();

        // Ancien point hors tracé (6 min) : la déviation est persistée.
        $trip->locations()->create([
            'latitude' => 4.2000,
            'longitude' => 12.0000,
            'vitesse_km_h' => 40,
            'captured_at' => now()->subMinutes(6),
        ]);

        // Deux POSTs frais (même passager, même type DETOUR) → pas de doublon.
        foreach ([0, 1] as $i) {
            $this->actingAs($passager)->postJson("/api/v1/trips/{$trip->id}/locations", [
                'latitude' => 4.2000,
                'longitude' => 12.0000,
                'vitesse_km_h' => 40,
                'captured_at' => now()->toIso8601String(),
            ])->assertCreated();
        }

        $this->assertDatabaseCount('anomaly_verifications', 1);
    }
}