<?php

namespace Tests\Feature;

use App\Models\Role;
use App\Models\Trip;
use App\Models\TripRating;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

/**
 * Couverture des endpoints encore non testés :
 * register, logout, deleteAccount, trips/status, voice/verify-cloud, ai/anomalies.
 */
class IntegrationGapTest extends TestCase
{
    use RefreshDatabase;

    private function role(string $slug): Role
    {
        return Role::firstOrCreate(['slug' => $slug], ['nom' => ucfirst($slug)]);
    }

    private function user(string $email, string $roleSlug = 'passager', array $overrides = []): User
    {
        $user = User::create(array_merge([
            'nom' => 'Test',
            'prenom' => 'User',
            'email' => $email,
            'telephone' => '6990000' . random_int(0, 9) . random_int(0, 9),
            'password' => Hash::make('password123'),
            'statut' => 'ACTIF',
        ], $overrides));
        $user->roles()->attach($this->role($roleSlug));

        return $user;
    }

    // ── register ──

    public function test_register_creates_passager_and_returns_token(): void
    {
        $this->role('passager');

        $response = $this->postJson('/api/v1/auth/register', [
            'nom' => 'Mballa',
            'prenom' => 'Ines',
            'email' => 'ines@saferide.app',
            'telephone' => '690111111',
            'password' => 'motdepasse123',
        ]);

        $response->assertStatus(201)
            ->assertJsonPath('message', 'Inscription réussie — vérifiez votre email')
            ->assertJsonPath('user.email', 'ines@saferide.app')
            ->assertJsonPath('user.roles.0', 'passager');

        $this->assertNotEmpty($response->json('token'));
        $this->assertDatabaseHas('users', ['email' => 'ines@saferide.app']);
    }

    public function test_register_with_role_transporteur(): void
    {
        $this->role('transporteur');

        $response = $this->postJson('/api/v1/auth/register', [
            'nom' => 'Tayo',
            'prenom' => 'Brice',
            'email' => 'brice@saferide.app',
            'telephone' => '690222222',
            'password' => 'motdepasse123',
            'role' => 'transporteur',
        ]);

        $response->assertStatus(201)
            ->assertJsonPath('user.roles.0', 'transporteur');
    }

    public function test_register_rejects_duplicate_email(): void
    {
        $this->role('passager');
        $this->user('dup@saferide.app');

        $this->postJson('/api/v1/auth/register', [
            'nom' => 'X',
            'prenom' => 'Y',
            'email' => 'dup@saferide.app',
            'telephone' => '690333333',
            'password' => 'motdepasse123',
        ])->assertStatus(422);
    }

    public function test_register_rejects_short_password(): void
    {
        $this->role('passager');

        $this->postJson('/api/v1/auth/register', [
            'nom' => 'X',
            'prenom' => 'Y',
            'email' => 'short@saferide.app',
            'telephone' => '690444444',
            'password' => 'courte',
        ])->assertStatus(422);
    }

    // ── logout ──

    public function test_logout_deletes_current_token(): void
    {
        $user = $this->user('logout@saferide.app');
        $token = $user->createToken('auth')->plainTextToken;

        // Flux réel mobile : Bearer token (pas actingAs, qui est un TransientToken).
$this->withHeaders(['Authorization' => "Bearer $token"])
            ->postJson('/api/v1/auth/logout')
            ->assertOk()
            ->assertJsonPath('message', 'Déconnexion réussie');

        // Critère de sécurité réel : le token est révoqué en base.
        $this->assertSame(0, $user->tokens()->count());
        $this->assertNull(\Laravel\Sanctum\PersonalAccessToken::findToken($token));
    }

    public function test_logout_requires_authentication(): void
    {
        $this->postJson('/api/v1/auth/logout')->assertStatus(401);
    }

    // ── deleteAccount ──

    public function test_delete_account_removes_user(): void
    {
        $user = $this->user('supprime@saferide.app');

        $this->actingAs($user)->deleteJson('/api/v1/auth/account')
            ->assertOk()
            ->assertJsonPath('message', 'Compte supprimé avec succès');

        $this->assertDatabaseMissing('users', ['id' => $user->id]);
    }

    public function test_delete_account_requires_authentication(): void
    {
        $this->deleteJson('/api/v1/auth/account')->assertStatus(401);
    }

    // ── trips/status ──

    public function test_trip_status_for_participant(): void
    {
        [$passager, $transporteur, $vehicle] = $this->scanSetup();

        $trip = $this->actingAs($passager)->postJson('/api/v1/trips/start', [
            'token' => $vehicle['qr_codes'][0]['token'],
            'latitude' => 3.8480,
            'longitude' => 11.5021,
        ])->assertCreated()->json('trip');

        // Le transporteur est aussi autorisé (il fait partie du trajet).
        $this->actingAs($transporteur)
            ->getJson("/api/v1/trips/{$trip['id']}/status")
            ->assertOk()
            ->assertJsonPath('trip.id', $trip['id']);

        $this->actingAs($passager)
            ->getJson("/api/v1/trips/{$trip['id']}/status")
            ->assertOk()
            ->assertJsonPath('trip.statut', 'SCANNE');
    }

    public function test_trip_status_denied_for_non_participant(): void
    {
        [$passager, , $vehicle] = $this->scanSetup();
        $intruder = $this->user('intrus@saferide.app');

        $trip = $this->actingAs($passager)->postJson('/api/v1/trips/start', [
            'token' => $vehicle['qr_codes'][0]['token'],
            'latitude' => 3.8480,
            'longitude' => 11.5021,
        ])->assertCreated()->json('trip');

        $this->actingAs($intruder)
            ->getJson("/api/v1/trips/{$trip['id']}/status")
            ->assertStatus(404);
    }

    public function test_trip_status_404_when_unknown(): void
    {
        $user = $this->user('inconnu@saferide.app');
        $this->actingAs($user)->getJson('/api/v1/trips/999999/status')->assertStatus(404);
    }

    // ── voice/verify-cloud ──

    public function test_verify_cloud_identical_embeddings_pass(): void
    {
        $user = $this->user('voix@saferide.app');
        $empreinte = array_fill(0, 192, 0.1);

        $res = $this->actingAs($user)->postJson('/api/v1/voice/verify-cloud', [
            'empreinte' => $empreinte,
            'test_empreinte' => $empreinte,
        ])->assertOk()->assertJsonPath('passed', true);

        $this->assertEqualsWithDelta(1.0, $res->json('cosine'), 1e-9);
    }

    public function test_verify_cloud_different_embeddings_fail(): void
    {
        $user = $this->user('voix2@saferide.app');
        $a = array_fill(0, 192, 0.1);
        $b = array_fill(0, 192, -0.1);

        $this->actingAs($user)->postJson('/api/v1/voice/verify-cloud', [
            'empreinte' => $a,
            'test_empreinte' => $b,
        ])->assertOk()
            ->assertJsonPath('passed', false);
    }

    public function test_verify_cloud_rejects_wrong_size(): void
    {
        $user = $this->user('voix3@saferide.app');

        $this->actingAs($user)->postJson('/api/v1/voice/verify-cloud', [
            'empreinte' => [0.1, 0.2],
            'test_empreinte' => [0.1, 0.2],
        ])->assertStatus(422);
    }

    // ── ai/anomalies (gestionnaire/admin) ──

    public function test_ai_anomalies_allowed_for_manager(): void
    {
        $manager = $this->user('manager-ia@saferide.app', 'gestionnaire');

        $this->actingAs($manager)->getJson('/api/v1/ai/anomalies')
            ->assertOk()
            ->assertJsonStructure(['report', 'insights']);
    }

    public function test_ai_anomalies_denied_for_passager(): void
    {
        $passager = $this->user('passager-ia@saferide.app');

        $this->actingAs($passager)->getJson('/api/v1/ai/anomalies')
            ->assertStatus(403);
    }

    // ── helpers ──

    private function scanSetup(): array
    {
        $transporteur = $this->user('t-gap@saferide.app', 'transporteur');
        $passager = $this->user('p-gap@saferide.app');

        $vehicle = $this->actingAs($transporteur)->postJson('/api/v1/vehicles', [
            'marque' => 'Toyota',
            'modele' => 'Corolla',
            'immatriculation' => 'LT-GAP-AB',
            'type' => 'VOITURE',
        ])->assertCreated()->json('vehicle');

        $this->actingAs($transporteur)->postJson("/api/v1/vehicles/{$vehicle['id']}/position", [
            'latitude' => 3.8480,
            'longitude' => 11.5021,
        ])->assertOk();

        return [$passager, $transporteur, $vehicle];
    }
}