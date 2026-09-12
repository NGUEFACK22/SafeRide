<?php

namespace Tests\Feature;

use App\Models\ManagerAssignment;
use App\Models\Role;
use App\Models\SosAlert;
use App\Models\Trip;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Password;
use Tests\TestCase;

/**
 * Couvre les processus métier restants (hors flux anomalie) :
 * rating, gestionnaire (SOS/litige), dashboard transporteur,
 * push token, decline-course, update-destination, auto-end,
 * SOS my/resolve, assistant IA, admin, mot de passe.
 */
class ProcessCoverageTest extends TestCase
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
     * Crée transporteur + véhicule avec QR, retourne [passager, transporteur, vehicle].
     */
    private function passengers(): array
    {
        Http::fake(['*' => Http::response('', 500)]);

        $transporteur = $this->user('transporteur@coverage.com', '690000020', 'transporteur');
        $passager = $this->user('passager@coverage.com', '690000021', 'passager');

        $vehicle = $this->actingAs($transporteur)->postJson('/api/v1/vehicles', [
            'marque' => 'Toyota',
            'modele' => 'Corolla',
            'immatriculation' => 'LT-001-AB',
            'type' => 'VOITURE',
        ])->assertCreated()->json('vehicle');

        $this->actingAs($transporteur)->postJson("/api/v1/vehicles/{$vehicle['id']}/position", [
            'latitude' => 3.8480,
            'longitude' => 11.5021,
        ])->assertOk();

        return [$passager, $transporteur, $vehicle];
    }

    /**
     * Trajet jusqu'à EN_ATTENTE_TRANSPORTEUR (course proposée au transporteur).
     */
    private function pendingTrip(): array
    {
        [$passager, $transporteur, $vehicle] = $this->passengers();

        $trip = $this->actingAs($passager)->postJson('/api/v1/trips/start', [
            'token' => $vehicle['qr_codes'][0]['token'],
            'latitude' => 3.8480,
            'longitude' => 11.5021,
        ])->assertCreated()->json('trip');

        $this->postJson("/api/v1/trips/{$trip['id']}/confirm-embarquement")->assertOk();

        return [$passager, $transporteur, Trip::findOrFail($trip['id'])];
    }

    /**
     * Trajet jusqu'à EN_COURS (destination confirmée).
     */
    private function ongoingTrip(): array
    {
        [$passager, $transporteur] = $this->pendingTrip();
        $trip = Trip::where('passager_id', $passager->id)->latest('id')->firstOrFail();

        $this->actingAs($transporteur)->postJson("/api/v1/trips/{$trip->id}/accept-course")->assertOk();
        $this->postJson("/api/v1/trips/{$trip->id}/destination", [
            'destination_address' => 'Akwa, Douala',
            'latitude' => 3.8700,
            'longitude' => 11.5210,
        ])->assertOk();
        $this->postJson("/api/v1/trips/{$trip->id}/confirm-destination", [
            'confirmed' => true,
        ])->assertOk();

        $this->assertEquals('EN_COURS', $trip->fresh()->statut);

        return [$passager, $transporteur, $trip];
    }

    /** Trajet terminé (TERMINE). */
    private function doneTrip(): array
    {
        [$passager, $transporteur, $trip] = $this->ongoingTrip();
        $this->actingAs($transporteur)->postJson("/api/v1/trips/{$trip->id}/end")->assertOk();

        return [$passager, $transporteur, $trip];
    }

    // ===================== Rating =====================

    public function test_rating_requires_participant_and_terminated_trip(): void
    {
        [$passager, , $trip] = $this->ongoingTrip();
        $outsider = $this->user('outsider@coverage.com', '690000022', 'passager');

        // Trajet encore en cours → 422.
        $this->actingAs($passager)->postJson("/api/v1/trips/{$trip->id}/rate", [
            'rating' => 5,
        ])->assertStatus(422);

        // Utilisateur extérieur au trajet → 403.
        $trip->update(['statut' => 'TERMINE']);
        $this->actingAs($outsider)->postJson("/api/v1/trips/{$trip->id}/rate", [
            'rating' => 5,
        ])->assertStatus(403);

        // Node invalide → 422.
        $this->actingAs($passager)->postJson("/api/v1/trips/{$trip->id}/rate", [
            'rating' => 9,
        ])->assertStatus(422);
    }

    public function test_rating_full_lifecycle(): void
    {
        [$passager, $transporteur, $trip] = $this->doneTrip();

        $created = $this->actingAs($passager)->postJson("/api/v1/trips/{$trip->id}/rate", [
            'rating' => 5,
            'comment' => 'Excellent trajet',
        ])->assertCreated()->json('rating');

        $this->assertSame($transporteur->id, $created['rated']['id']);
        $this->assertDatabaseHas('trip_ratings', [
            'trip_id' => $trip->id,
            'rater_id' => $passager->id,
            'rated_id' => $transporteur->id,
            'rating' => 5,
        ]);

        // Double notation impossible → 409.
        $this->actingAs($passager)->postJson("/api/v1/trips/{$trip->id}/rate", [
            'rating' => 4,
        ])->assertStatus(409);

        // Modification par PUT.
        $this->actingAs($passager)->putJson("/api/v1/trips/{$trip->id}/rate", [
            'rating' => 4,
            'comment' => 'Améliorable',
        ])->assertOk()
            ->assertJsonPath('rating.rating', 4);

        // Consultation des avis du trajet (moyenne recalculée).
        $this->actingAs($passager)->getJson("/api/v1/trips/{$trip->id}/ratings")
            ->assertOk()
            ->assertJsonPath('count', 1)
            ->assertJsonPath('average', 4);

        // Notes reçues par le transporteur.
        $this->actingAs($transporteur)->getJson('/api/v1/ratings/received')
            ->assertOk()
            ->assertJsonCount(1, 'ratings.data')
            ->assertJsonPath('stats.average', 4);

        // Notes données par le passager.
        $this->actingAs($passager)->getJson('/api/v1/ratings/given')
            ->assertOk()
            ->assertJsonCount(1, 'ratings.data');

        // Stats publiques.
        $this->actingAs($passager)->getJson("/api/v1/users/{$transporteur->id}/ratings/stats")
            ->assertOk()
            ->assertJsonPath('stats.count', 1)
            ->assertJsonPath('stats.distribution.4', 1);

        $this->assertDatabaseHas('notifications', [
            'user_id' => $transporteur->id,
            'type' => 'TRAJET',
        ]);
    }

    // ===================== Gestionnaire =====================

    public function test_manager_sos_workflow_take_then_close(): void
    {
        $manager = $this->user('manager@coverage.com', '690000023', 'gestionnaire');
        $passager = $this->user('passager2@coverage.com', '690000024', 'passager');

        $sos = $this->actingAs($passager)->postJson('/api/v1/sos', [
            'latitude' => 3.8480,
            'longitude' => 11.5021,
            'declenchement' => 'BOUTON',
        ])->assertCreated()->json('sos');

        // L'alerte est attribuée au gestionnaire (SOS + litige créé).
        $this->assertDatabaseHas('disputes', ['passager_id' => $passager->id, 'statut' => 'OUVERT']);
        $this->assertDatabaseHas('manager_assignments', [
            'manager_id' => $manager->id,
            'dossier_type' => 'SOS',
            'statut' => 'ATTRIBUE',
        ]);

        // Dashboard : 2 dossiers ouverts (SOS + litige).
        $this->actingAs($manager)->getJson('/api/v1/manager/dashboard')
            ->assertOk()
            ->assertJsonPath('open', 2)
            ->assertJsonPath('closed', 0)
            ->assertJsonPath('total', 2);

        // Liste des dossiers.
        $this->actingAs($manager)->getJson('/api/v1/manager/assignments')
            ->assertOk()
            ->assertJsonCount(2, 'assignments.data');

        // Prise en charge → dossier SOS et alerte EN_COURS.
        $assignment = ManagerAssignment::where('dossier_type', 'SOS')->firstOrFail();
        $this->actingAs($manager)->postJson("/api/v1/manager/assignments/{$assignment->id}/take")
            ->assertOk()
            ->assertJsonPath('assignment.statut', 'PRIS_EN_CHARGE');
        $this->assertNotNull($assignment->fresh()->taken_at);
        $this->assertSame('EN_COURS', SosAlert::findOrFail($sos['id'])->statut);

        // Clôture → alerte CLOTE.
        $this->actingAs($manager)->postJson("/api/v1/manager/assignments/{$assignment->id}/close")
            ->assertOk()
            ->assertJsonPath('assignment.statut', 'CLOTURE');
        $this->assertSame('CLOTE', SosAlert::findOrFail($sos['id'])->statut);

        // Re-take impossible après clôture (422/404).
        $this->actingAs($manager)->postJson("/api/v1/manager/assignments/{$assignment->id}/take")
            ->assertStatus(404);
    }

    public function test_sos_my_alerts_and_resolve(): void
    {
        $manager = $this->user('manager2@coverage.com', '690000025', 'gestionnaire');
        $passager = $this->user('passager3@coverage.com', '690000026', 'passager');

        $this->actingAs($passager)->postJson('/api/v1/sos', [
            'latitude' => 3.8480,
            'longitude' => 11.5021,
            'declenchement' => 'BOUTON',
        ])->assertCreated();

        // Liste personnelle du passager.
        $this->actingAs($passager)->getJson('/api/v1/sos/my')
            ->assertOk()
            ->assertJsonCount(1, 'alerts.data');

        // Consultation + résolution par le gestionnaire.
        $sosId = SosAlert::latest('id')->value('id');

        $this->actingAs($manager)->getJson("/api/v1/sos/{$sosId}")
            ->assertOk()
            ->assertJsonPath('sos.id', $sosId);

        $this->actingAs($manager)->putJson("/api/v1/sos/{$sosId}/resolve", [
            'statut' => 'RESOLU',
            'details' => ['issue' => 'fausse alerte'],
        ])->assertOk()->assertJsonPath('sos.statut', 'RESOLU');
    }

    // ===================== Dashboard transporteur =====================

    public function test_transporteur_dashboard_aggregates_real_trips_only(): void
    {
        [$passager, $transporteur, $trip] = $this->doneTrip();

        $this->actingAs($passager)->postJson("/api/v1/trips/{$trip->id}/rate", [
            'rating' => 5,
        ])->assertCreated();

        $this->actingAs($transporteur)->getJson('/api/v1/transporteur/dashboard')
            ->assertOk()
            ->assertJsonPath('vehicles_count', 1)
            ->assertJsonPath('trips.total', 1)
            ->assertJsonPath('trips.termine', 1)
            ->assertJsonPath('trips.en_cours', 0)
            ->assertJsonPath('passagers_distinct', 1)
            ->assertJsonPath('ratings.count', 1)
            ->assertJsonPath('ratings.average', 5);
    }

    // ===================== Push token FCM =====================

    public function test_push_token_store_upsert_and_validation(): void
    {
        $passager = $this->user('push1@coverage.com', '690000027', 'passager');
        $envoyeur = $this->user('push2@coverage.com', '690000028', 'passager');

        $this->actingAs($passager)->postJson('/api/v1/push-token', [
            'token' => 'fcm-abc-123',
            'device' => 'Pixel 9',
        ])->assertOk()->assertJsonPath('message', 'Token enregistré');
        $this->assertDatabaseCount('fcm_tokens', 1);

        // Même token (même user) → upsert, pas de doublon.
        $this->actingAs($passager)->postJson('/api/v1/push-token', [
            'token' => 'fcm-abc-123',
            'device' => 'Pixel 9 Pro',
        ])->assertOk();
        $this->assertDatabaseCount('fcm_tokens', 1);

        // Même token, autre user → le token change de propriétaire.
        $this->actingAs($envoyeur)->postJson('/api/v1/push-token', [
            'token' => 'fcm-abc-123',
        ])->assertOk();
        $this->assertDatabaseCount('fcm_tokens', 1);
        $this->assertDatabaseHas('fcm_tokens', [
            'token' => 'fcm-abc-123',
            'user_id' => $envoyeur->id,
        ]);

        // Token manquant → 422.
        $this->actingAs($passager)->postJson('/api/v1/push-token', [])
            ->assertStatus(422);
    }

    // ===================== Decline + pending =====================

    public function test_transporteur_pending_and_decline_course(): void
    {
        [$passager, $transporteur, $trip] = $this->pendingTrip();
        $this->assertSame('EN_ATTENTE_TRANSPORTEUR', $trip->statut);

        // Le transporteur voit la course proposée.
        $this->actingAs($transporteur)->getJson('/api/v1/trips/pending')
            ->assertOk()
            ->assertJsonPath('trip.id', $trip->id);

        // Refus → ANNULE + notification au passager.
        $this->actingAs($transporteur)->postJson("/api/v1/trips/{$trip->id}/decline-course")
            ->assertOk()
            ->assertJsonPath('trip.statut', 'ANNULE');

        $this->assertSame('REFUS_TRANSPORTEUR', $trip->fresh()->end_method);
        $this->assertDatabaseHas('notifications', [
            'user_id' => $passager->id,
            'type' => 'TRAJET',
        ]);

        // Plus rien en attente pour le transporteur.
        $this->actingAs($transporteur)->getJson('/api/v1/trips/pending')
            ->assertOk()
            ->assertJsonPath('trip', null);
    }

    public function test_accept_course_then_update_destination(): void
    {
        [$passager, $transporteur, $trip] = $this->pendingTrip();

        $this->actingAs($transporteur)->postJson("/api/v1/trips/{$trip->id}/accept-course")->assertOk();
        $trip = $trip->fresh();
        $this->assertSame('CONFIRME', $trip->statut);

        $this->postJson("/api/v1/trips/{$trip->id}/destination", [
            'destination_address' => 'Bonanjo, Douala',
            'latitude' => 3.8800,
            'longitude' => 11.5120,
        ])->assertOk();
        $trip = $trip->fresh();
        $this->assertSame('DESTINATION_PROPOSEE', $trip->statut);

        // Modification en cours de trajet → nouvelle adresse proposée.
        $this->postJson("/api/v1/trips/{$trip->id}/update-destination", [
            'destination_address' => 'Akwa, Douala',
            'latitude' => 3.8700,
            'longitude' => 11.5210,
        ])->assertOk()
            ->assertJsonPath('trip.destination_address', 'Akwa, Douala');

        $this->postJson("/api/v1/trips/{$trip->id}/confirm-destination", [
            'confirmed' => true,
        ])->assertOk();
        $this->assertSame('EN_COURS', $trip->fresh()->statut);
    }

    // ===================== Auto-end =====================

    public function test_auto_end_inactive_finalizes_stale_active_trip(): void
    {
        [$passager, , $trip] = $this->ongoingTrip();
        $admin = $this->user('admin@coverage.com', '690000029', 'admin');

        // Simule une course sans activité depuis 11 min.
        Trip::where('id', $trip->id)->update(['started_at' => now()->subMinutes(11)]);

        $this->actingAs($admin)->postJson('/api/v1/trips/auto-end-inactive')
            ->assertOk()
            ->assertJsonPath('closed', 1);

        $this->assertSame('TERMINE', $trip->fresh()->statut);
        $this->assertSame('AUTO_10MIN', $trip->fresh()->end_method);
    }

    public function test_auto_end_inactive_purges_orphan_configuration(): void
    {
        [$passager] = $this->pendingTrip();
        $admin = $this->user('admin2@coverage.com', '690000030', 'admin');

        // Le passager a scanné mais n'a pas donné suite depuis 20 min.
        Trip::where('passager_id', $passager->id)->update(['started_at' => now()->subMinutes(20)]);
        $this->assertSame('EN_ATTENTE_TRANSPORTEUR', Trip::where('passager_id', $passager->id)->first()->statut);

        $this->actingAs($admin)->postJson('/api/v1/trips/auto-end-inactive')
            ->assertOk();

        $trip = Trip::where('passager_id', $passager->id)->first();
        $this->assertSame('ANNULE', $trip->statut);
        $this->assertSame('AUTO_10MIN', $trip->end_method);
    }

    // ===================== Assistant IA =====================

    public function test_ai_summary_and_trip_summary_fallback(): void
    {
        [$passager, , $trip] = $this->doneTrip();

        $this->actingAs($passager)->getJson('/api/v1/ai/summary')
            ->assertOk()
            ->assertJsonStructure(['report' => ['contenu']]);

        $this->actingAs($passager)->getJson("/api/v1/ai/trips/{$trip->id}")
            ->assertOk()
            ->assertJsonStructure(['report' => ['contenu'], 'insights']);
    }

    // ===================== Admin =====================

    public function test_admin_manager_stats(): void
    {
        $admin = $this->user('admin3@coverage.com', '690000031', 'admin');
        $manager = $this->user('manager3@coverage.com', '690000032', 'gestionnaire');

        ManagerAssignment::create([
            'manager_id' => $manager->id,
            'dossier_type' => 'LITIGE',
            'dossier_id' => 1,
            'statut' => 'CLOTURE',
        ]);
        // L'assignation SOS de create() utilisée ailleurs n'existe pas ici.

        $this->actingAs($admin)->getJson("/api/v1/admin/managers/{$manager->id}/stats")
            ->assertOk()
            ->assertJsonPath('total', 1)
            ->assertJsonPath('par_statut.CLOTURE', 1);

        $this->actingAs($admin)->getJson('/api/v1/admin/managers/stats')
            ->assertOk()
            ->assertJsonCount(1, 'managers');
    }

    // ===================== Mot de passe =====================

    public function test_forgot_and_reset_password(): void
    {
        $user = $this->user('mra@coverage.com', '690000033', 'passager');

        $this->postJson('/api/v1/auth/forgot-password', ['email' => 'mra@coverage.com'])
            ->assertOk()
            ->assertJsonPath('message', 'Lien de réinitialisation envoyé par email');

        $this->postJson('/api/v1/auth/forgot-password', ['email' => 'inconnu@coverage.com'])
            ->assertStatus(404);

        $token = Password::broker()->createToken($user);

        $this->postJson('/api/v1/auth/reset-password', [
            'email' => 'mra@coverage.com',
            'token' => $token,
            'password' => 'nouveau-motdepasse',
            'password_confirmation' => 'nouveau-motdepasse',
        ])->assertOk()
            ->assertJsonPath('message', 'Mot de passe réinitialisé avec succès');

        // Ancien mot de passe invalide, nouveau fonctionne.
        $this->postJson('/api/v1/auth/login', [
            'email' => 'mra@coverage.com',
            'password' => 'password',
        ])->assertStatus(401);

        $this->postJson('/api/v1/auth/login', [
            'email' => 'mra@coverage.com',
            'password' => 'nouveau-motdepasse',
        ])->assertOk();

        // Token périmé → 422.
        $this->postJson('/api/v1/auth/reset-password', [
            'email' => 'mra@coverage.com',
            'token' => 'mauvais-token',
            'password' => 'encore-un-pass',
            'password_confirmation' => 'encore-un-pass',
        ])->assertStatus(422);
    }
}