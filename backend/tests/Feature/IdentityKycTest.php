<?php

namespace Tests\Feature;

use App\Models\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class IdentityKycTest extends TestCase
{
    use RefreshDatabase;

    /** @var list<string> */
    private array $tempFiles = [];

    protected function tearDown(): void
    {
        foreach ($this->tempFiles as $name) {
            @unlink(storage_path('app/'.$name));
        }
        parent::tearDown();
    }

    private function user(string $email, string $telephone, string $roleSlug = 'passager'): User
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

    /** Crée un fichier document local (contourne l'extension PHP GD absente). */
    private function fakeDocument(): string
    {
        $name = 'cni_test_'.uniqid().'.jpg';
        file_put_contents(storage_path('app/'.$name), 'fake-jpeg-bytes');
        $this->tempFiles[] = $name;

        return $name;
    }

    private function fakeDidit(string $decision): void
    {
        Http::fake([
            '*' => Http::response([
                'status' => 'ok',
                'id_verification' => [
                    'status' => $decision,
                    'form_values' => ['document_number' => 'CM1234567'],
                ],
            ], 200),
        ]);
    }

    public function test_kyc_submit_with_approved_didit_response(): void
    {
        config(['services.didit.key' => 'test-didit-key']);
        $this->fakeDidit('approved');

        $user = $this->user('passager@example.com', '690000020');
        $this->actingAs($user);

        $response = $this->post('/api/v1/identity/submit', [
            'type' => 'CNI',
            'numero' => 'CM1234567',
            'fichier_url' => $this->fakeDocument(),
        ])->assertCreated();

        $this->assertEquals('VERIFIE', $response->json('verification.statut'));
        $this->assertEquals('didit', $response->json('verification.provider_kyc'));

        // Statut récupéré par le mobile.
        $status = $this->getJson('/api/v1/identity/status')->assertOk()->json();
        $this->assertTrue($status['identite_verifiee']);
    }

    public function test_kyc_submit_with_declined_didit_response(): void
    {
        config(['services.didit.key' => 'test-didit-key']);
        $this->fakeDidit('declined');

        $user = $this->user('passager@example.com', '690000021');
        $this->actingAs($user);

        $response = $this->post('/api/v1/identity/submit', [
            'type' => 'PASSEPORT',
            'fichier_url' => $this->fakeDocument(),
        ])->assertCreated();

        $this->assertEquals('ECHOUE', $response->json('verification.statut'));
    }

    public function test_kyc_without_didit_key_falls_back_to_manual_review(): void
    {
        config(['services.didit.key' => '']);

        $user = $this->user('passager@example.com', '690000022');
        $this->actingAs($user);

        $response = $this->post('/api/v1/identity/submit', [
            'type' => 'CNI',
            'fichier_url' => $this->fakeDocument(),
        ])->assertCreated();

        $this->assertEquals('EN_ATTENTE', $response->json('verification.statut'));
    }

    public function test_manager_reviews_pending_identity(): void
    {
        config(['services.didit.key' => '']);

        $passager = $this->user('passager@example.com', '690000023');
        $this->actingAs($passager);

        $submitted = $this->post('/api/v1/identity/submit', [
            'type' => 'CNI',
            'fichier_url' => $this->fakeDocument(),
        ])->assertCreated()->json('verification');

        $manager = $this->user('manager@example.com', '690000024', 'gestionnaire');
        $this->actingAs($manager);

        // Le dossier en attente est visible par le gestionnaire.
        $pending = $this->getJson('/api/v1/identity/pending')->assertOk()->json('verifications');
        $this->assertNotEmpty($pending);

        // Revue manuelle → VERIFIE.
        $this->putJson("/api/v1/identity/{$submitted['id']}/review", [
            'statut' => 'VERIFIE',
            'provider_kyc' => 'manuel',
        ])->assertOk();

        $this->assertDatabaseHas('identity_verifications', [
            'id' => $submitted['id'],
            'statut' => 'VERIFIE',
        ]);
    }
}