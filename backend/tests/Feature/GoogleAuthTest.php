<?php

namespace Tests\Feature;

use App\Models\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class GoogleAuthTest extends TestCase
{
    use RefreshDatabase;

    protected function fakeTokeninfo(array $claims): void
    {
        Http::fake([
            'oauth2.googleapis.com/tokeninfo*' => Http::response($claims, 200),
        ]);
    }

    public function test_google_login_creates_account_when_email_unknown(): void
    {
        Role::firstOrCreate(['slug' => 'passager'], ['nom' => 'Passager']);

        $this->fakeTokeninfo([
            'sub' => 'google-sub-123',
            'email' => 'nouveau@gmail.com',
            'email_verified' => true,
            'aud' => 'mon-client-web',
            'given_name' => 'Jean',
            'family_name' => 'Dupont',
            'name' => 'Jean Dupont',
            'picture' => 'https://lh3.googleusercontent.com/photo',
        ]);

        config()->set('services.google.client_id', 'mon-client-web');

        $response = $this->postJson('/api/v1/auth/google', ['id_token' => 'jeton-fake']);

        $response->assertStatus(200)
            ->assertJsonPath('message', 'Connexion Google réussie')
            ->assertJsonPath('user.email', 'nouveau@gmail.com')
            ->assertJsonPath('user.prenom', 'Jean')
            ->assertJsonPath('user.nom', 'Dupont')
            ->assertJsonPath('user.photo_url', 'https://lh3.googleusercontent.com/photo');

        $this->assertDatabaseHas('users', [
            'email' => 'nouveau@gmail.com',
            'google_id' => 'google-sub-123',
        ]);

        $user = User::where('email', 'nouveau@gmail.com')->first();
        $this->assertTrue($user->hasRole('passager'));
        $this->assertNotEmpty($response->json('token'));
    }

    public function test_google_login_links_existing_account_by_email(): void
    {
        $this->fakeTokeninfo([
            'sub' => 'google-sub-456',
            'email' => 'existant@saferide.app',
            'aud' => 'mon-client-web',
            'given_name' => 'Marie',
            'family_name' => 'Curie',
        ]);

        config()->set('services.google.client_id', 'mon-client-web');

        $existing = User::factory()->create([
            'email' => 'existant@saferide.app',
            'telephone' => '699000001',
        ]);

        $response = $this->postJson('/api/v1/auth/google', ['id_token' => 'jeton-fake']);

        $response->assertStatus(200)
            ->assertJsonPath('user.id', $existing->id)
            ->assertJsonPath('user.email', 'existant@saferide.app');

        $this->assertDatabaseHas('users', [
            'id' => $existing->id,
            'google_id' => 'google-sub-456',
        ]);
    }

    public function test_google_login_rejects_invalid_token(): void
    {
        Http::fake([
            'oauth2.googleapis.com/tokeninfo*' => Http::response(['error_description' => 'Invalid Value'], 400),
        ]);

        $response = $this->postJson('/api/v1/auth/google', ['id_token' => 'jeton-pourri']);

        $response->assertStatus(401)
            ->assertJson(['message' => 'Jeton Google invalide']);
    }

    public function test_google_login_rejects_token_for_another_application(): void
    {
        $this->fakeTokeninfo([
            'sub' => 'google-sub-789',
            'email' => 'autre-app@gmail.com',
            'aud' => 'un-autre-client-id',
        ]);

        config()->set('services.google.client_id', 'mon-client-web');

        $this->postJson('/api/v1/auth/google', ['id_token' => 'jeton-fake'])
            ->assertStatus(401);
    }

    public function test_google_login_returns_403_for_suspended_account(): void
    {
        $this->fakeTokeninfo([
            'sub' => 'google-sub-susp',
            'email' => 'suspendu@saferide.app',
            'aud' => 'mon-client-web',
        ]);

        config()->set('services.google.client_id', 'mon-client-web');

        User::factory()->create([
            'email' => 'suspendu@saferide.app',
            'statut' => 'SUSPENDU',
        ]);

        $this->postJson('/api/v1/auth/google', ['id_token' => 'jeton-fake'])
            ->assertStatus(403);
    }
}