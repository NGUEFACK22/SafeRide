<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use App\Models\AnomalyVerification;
use App\Models\QrCode;
use App\Models\Role;
use App\Models\Trip;
use App\Models\User;
use App\Services\AiService;
use App\Services\QrTokenService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

/**
 * Robustesse du processus trajet : audit complet de la machine à états,
 * garde EN_COURS sur la clôture, signature QR vérifiée au scan, et watchdog
 * serveur de perte de signal GPS.
 */
class ProcessRobustnessTest extends TestCase
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
     * Cycle complet jusqu'à EN_COURS. Renvoie [passager, transporteur, trip].
     */
    private function ongoingTrip(): array
    {
        Http::fake(['*' => Http::response('', 500)]);
        config(['services.ai.enabled' => false]);

        $suffix = substr(uniqid(), -6);
        $transporteur = $this->user('tr-' . $suffix . '@robust.com', '69' . $suffix . '1', 'transporteur');
        $passager = $this->user('pa-' . $suffix . '@robust.com', '69' . $suffix . '2', 'passager');

        $vehicle = $this->actingAs($transporteur)->postJson('/api/v1/vehicles', [
            'marque' => 'Toyota',
            'modele' => 'Corolla',
            'immatriculation' => 'LT-' . mt_rand(1000, 9999) . '-RB',
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
            ->postJson("/api/v1/trips/{$start['id']}/accept-course")->assertOk();
        $this->postJson("/api/v1/trips/{$start['id']}/destination", [
            'destination_address' => 'Akwa, Douala',
            'latitude' => 3.8700,
            'longitude' => 11.5210,
        ])->assertOk();
        $this->postJson("/api/v1/trips/{$start['id']}/confirm-destination", [
            'confirmed' => true,
        ])->assertOk();

        $trip = Trip::findOrFail($start['id']);
        $this->assertSame('EN_COURS', $trip->statut);

        return [$passager, $transporteur, $trip];
    }

    public function test_trip_start_and_destination_confirmee_are_audited(): void
    {
        [, , $trip] = $this->ongoingTrip();

        // La traçabilité revendue par le sujet : chaque transition de la
        // machine à états laisse une ligne d'audit, y compris le départ.
        $actions = AuditLog::where('entity_type', 'Trip')
            ->where('entity_id', $trip->id)
            ->pluck('action')
            ->all();

        $this->assertContains('scan_qr', $actions);
        $this->assertContains('confirm_embarquement', $actions);
        $this->assertContains('course_acceptee', $actions);
        $this->assertContains('destination_proposee', $actions);
        $this->assertContains('destination_confirmee', $actions);
        $this->assertContains('trip_start', $actions);

        $startLog = AuditLog::where('entity_type', 'Trip')
            ->where('entity_id', $trip->id)
            ->where('action', 'trip_start')
            ->first();
        $this->assertSame('Akwa, Douala', $startLog->details['destination_address']);
    }

    public function test_manual_end_is_rejected_before_en_cours(): void
    {
        Http::fake(['*' => Http::response('', 500)]);
        config(['services.ai.enabled' => false]);

        [$passager, $transporteur] = [
            $this->user('pe-' . uniqid() . '@robust.com', '690000053', 'passager'),
            $this->user('te-' . uniqid() . '@robust.com', '690000054', 'transporteur'),
        ];

        $vehicle = $this->actingAs($transporteur)->postJson('/api/v1/vehicles', [
            'marque' => 'Toyota',
            'modele' => 'Corolla',
            'immatriculation' => 'LT-' . mt_rand(1000, 9999) . '-RB',
            'type' => 'VOITURE',
        ])->assertCreated()->json('vehicle');

        $this->actingAs($transporteur)->postJson("/api/v1/vehicles/{$vehicle['id']}/position", [
            'latitude' => 3.8480, 'longitude' => 11.5021,
        ])->assertOk();

        $trip = $this->actingAs($passager)->postJson('/api/v1/trips/start', [
            'token' => $vehicle['qr_codes'][0]['token'],
            'latitude' => 3.8480, 'longitude' => 11.5021,
        ])->assertCreated()->json('trip');

        $this->postJson("/api/v1/trips/{$trip['id']}/confirm-embarquement")->assertOk();
        $this->actingAs($transporteur)
            ->postJson("/api/v1/trips/{$trip['id']}/accept-course")->assertOk();

        // CONFIRME (jamais démarré) : clôture manuelle refusée, annulation dispo.
        $this->postJson("/api/v1/trips/{$trip['id']}/end")
            ->assertStatus(422)
            ->assertJsonPath('statut', null);

        $fresh = Trip::findOrFail($trip['id']);
        $this->assertSame('CONFIRME', $fresh->statut);
    }

    public function test_unsigned_or_tampered_qr_token_is_rejected(): void
    {
        Http::fake(['*' => Http::response('', 500)]);
        config(['services.ai.enabled' => false]);

        $transporteur = $this->user('tt-' . uniqid() . '@robust.com', '690000055', 'transporteur');
        $passager = $this->user('pp-' . uniqid() . '@robust.com', '690000056', 'passager');

        $vehicle = $this->actingAs($transporteur)->postJson('/api/v1/vehicles', [
            'marque' => 'Toyota',
            'modele' => 'Corolla',
            'immatriculation' => 'LT-' . mt_rand(1000, 9999) . '-RB',
            'type' => 'VOITURE',
        ])->assertCreated()->json('vehicle');

        $this->actingAs($transporteur)->postJson("/api/v1/vehicles/{$vehicle['id']}/position", [
            'latitude' => 3.8480, 'longitude' => 11.5021,
        ])->assertOk();

        // 1. Un QR "ancien format" (hex aléatoire, non signé) en base est refusé.
        $legacy = QrCode::create([
            'vehicle_id' => $vehicle['id'],
            'token' => bin2hex(random_bytes(16)),
            'actif' => true,
        ]);

        $this->actingAs($passager)->postJson('/api/v1/trips/start', [
            'token' => $legacy->token,
            'latitude' => 3.8480, 'longitude' => 11.5021,
        ])->assertStatus(422);

        // 2. Un payload signé dont le véhicule (vid) est falsifié → signature
        // recalculée impossible sans app.key → verify() renvoie null.
        $signed = app(QrTokenService::class)->generate(\App\Models\Vehicle::find($vehicle['id']));
        $raw = base64_decode($signed);
        $tampered = str_replace('"vid":' . $vehicle['id'], '"vid":99999', $raw);
        $this->assertNotSame($raw, $tampered);

        $this->actingAs($passager)->postJson('/api/v1/trips/start', [
            'token' => base64_encode($tampered),
            'latitude' => 3.8480, 'longitude' => 11.5021,
        ])->assertStatus(422);
    }

    public function test_qr_token_service_round_trip(): void
    {
        $transporteur = $this->user('rt-' . uniqid() . '@robust.com', '690000057', 'transporteur');
        $vehicle = \App\Models\Vehicle::create([
            'transporteur_id' => $transporteur->id,
            'marque' => 'Toyota',
            'modele' => 'Corolla',
            'immatriculation' => 'LT-' . mt_rand(1000, 9999) . '-RT',
            'type' => 'VOITURE',
            'statut' => 'ACTIF',
        ]);

        $svc = app(QrTokenService::class);
        $token = $svc->generate($vehicle);

        $payload = $svc->verify($token);
        $this->assertNotNull($payload);
        $this->assertSame($vehicle->id, (int) $payload['vid']);

        // Signe un payload altéré → invalide.
        $raw = base64_decode($token);
        $raw = str_replace('"vid":' . $vehicle->id, '"vid":99999', $raw);
        $this->assertNull($svc->verify(base64_encode($raw)));

        // Token expiré → invalide.
        $expired = base64_encode(json_encode([
            'vid' => $vehicle->id,
            'n' => 'abc',
            'exp' => now()->subDay()->timestamp,
        ]) . '.' . hash_hmac('sha256', json_encode([
            'vid' => $vehicle->id,
            'n' => 'abc',
            'exp' => now()->subDay()->timestamp,
        ]), (string) config('app.key')));
        $this->assertNull($svc->verify($expired));
    }

    public function test_stale_trip_watchdog_creates_movement_loss_for_both_parties(): void
    {
        [$passager, $transporteur, $trip] = $this->ongoingTrip();

        // Le trajet a démarré il y a 12 min et AUCUNE position n'est jamais
        // arrivée (téléphone éteint / hors-réseau) : la détection inline ne
        // peut pas la voir, seul le watchdog serveur le peut.
        Trip::where('id', $trip->id)->update(['started_at' => now()->subMinutes(12)]);

        $created = app(AiService::class)->checkStaleTrips();
        $this->assertSame(2, $created);

        foreach ([$passager->id, $transporteur->id] as $userId) {
            $verif = AnomalyVerification::where('trip_id', $trip->id)
                ->where('user_id', $userId)
                ->where('anomaly_type', 'MOVEMENT_LOSS')
                ->first();
            $this->assertNotNull($verif, "Vérification MOVEMENT_LOSS manquante pour $userId");
            $this->assertSame('EN_ATTENTE', $verif->statut);
        }

        // Idempotence : relancer ne crée pas de doublon.
        $this->assertSame(0, app(AiService::class)->checkStaleTrips());
        $this->assertSame(2, AnomalyVerification::where('trip_id', $trip->id)->count());

        // Un trajet récent n'est pas concerné.
        [$p2, $t2, $trip2] = $this->ongoingTrip();
        $this->assertSame(0, app(AiService::class)->checkStaleTrips());
        $this->assertSame(
            0,
            AnomalyVerification::where('trip_id', $trip2->id)
                ->where('anomaly_type', 'MOVEMENT_LOSS')->count()
        );
    }
}
