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

    public function test_route_deviation_notifies_both_parties(): void
    {
        [$trip, $passager, $transporteur] = $this->ongoingTrip();

        // Tracé prévu : ligne droite courte (start → destination).
        $routeService = app(RouteService::class);
        $trip->planned_route_polyline = $routeService->encodePolyline([
            [3.8480, 11.5021],
            [3.8700, 11.5210],
        ]);
        $trip->save();

        // Position GPS très éloignée du tracé (> 1 km) : déviation détectée.
        $this->actingAs($passager)->postJson("/api/v1/trips/{$trip->id}/locations", [
            'latitude' => 4.2000,
            'longitude' => 12.0000,
            'vitesse_km_h' => 40,
            'captured_at' => now()->toIso8601String(),
        ])->assertCreated();

        // Une vérification DETOUR par partie (passager + transporteur).
        $this->assertDatabaseCount('anomaly_verifications', 2);
        $this->assertDatabaseHas('anomaly_verifications', [
            'trip_id' => $trip->id,
            'user_id' => $passager->id,
            'anomaly_type' => 'DETOUR',
            'statut' => 'EN_ATTENTE',
        ]);
        $this->assertDatabaseHas('anomaly_verifications', [
            'trip_id' => $trip->id,
            'user_id' => $transporteur->id,
            'anomaly_type' => 'DETOUR',
            'statut' => 'EN_ATTENTE',
        ]);

        // Notification push envoyée aux DEUX parties.
        $this->assertDatabaseHas('notifications', [
            'user_id' => $passager->id,
            'type' => 'ANOMALIE_VERIFICATION',
        ]);
        $this->assertDatabaseHas('notifications', [
            'user_id' => $transporteur->id,
            'type' => 'ANOMALIE_VERIFICATION',
        ]);
    }

    public function test_prolonged_stop_notifies_both_parties(): void
    {
        [$trip, $passager, $transporteur] = $this->ongoingTrip();

        // 5 positions à vitesse quasi nulle (< 2 km/h) sur 6 minutes.
        for ($i = 0; $i < 5; $i++) {
            $this->actingAs($passager)->postJson("/api/v1/trips/{$trip->id}/locations", [
                'latitude' => 3.8480,
                'longitude' => 11.5021,
                'vitesse_km_h' => 0,
                'captured_at' => now()->subMinutes(6 - $i)->toIso8601String(),
            ])->assertCreated();
        }

        $this->assertDatabaseCount('anomaly_verifications', 2);
        $this->assertDatabaseHas('anomaly_verifications', [
            'trip_id' => $trip->id,
            'user_id' => $passager->id,
            'anomaly_type' => 'STOP',
            'statut' => 'EN_ATTENTE',
        ]);
        $this->assertDatabaseHas('anomaly_verifications', [
            'trip_id' => $trip->id,
            'user_id' => $transporteur->id,
            'anomaly_type' => 'STOP',
            'statut' => 'EN_ATTENTE',
        ]);
    }

    public function test_three_min_timeout_triggers_sos_on_unresponded_party(): void
    {
        [$trip, $passager, $transporteur] = $this->ongoingTrip();

        // Vérification du transporteur créée il y a 4 min, jamais répondue.
        $verif = new AnomalyVerification;
        $verif->trip_id = $trip->id;
        $verif->user_id = $transporteur->id;
        $verif->anomaly_type = 'DETOUR';
        $verif->description = 'Déviation non confirmée.';
        $verif->gravite = 'ELEVEE';
        $verif->statut = 'EN_ATTENTE';
        $verif->created_at = now()->subMinutes(4);
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
        ]);
    }

    public function test_no_duplicate_verification_per_party(): void
    {
        [$trip, $passager, $transporteur] = $this->ongoingTrip();

        // Deux détections identiques (même partie, même type) → pas de doublon.
        foreach ([0, 1] as $i) {
            $ping = app(RouteService::class);
            $trip->planned_route_polyline = $ping->encodePolyline([
                [3.8480, 11.5021],
                [3.8700, 11.5210],
            ]);
            $trip->save();

            $this->actingAs($passager)->postJson("/api/v1/trips/{$trip->id}/locations", [
                'latitude' => 4.2000,
                'longitude' => 12.0000,
                'vitesse_km_h' => 40,
                'captured_at' => now()->toIso8601String(),
            ])->assertCreated();
        }

        $this->assertDatabaseCount('anomaly_verifications', 2);
    }
}