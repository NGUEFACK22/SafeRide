<?php

namespace Tests\Feature;

use App\Models\Role;
use App\Models\User;
use App\Services\AiService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

/**
 * POST /ai/ask — l'assistant ne répond qu'aux questions liées à SafeRide.
 * IA désactivée (config par défaut) => REGLE : pré-filtre des termes + réponses standard.
 */
class AiAskTest extends TestCase
{
    use RefreshDatabase;

    private function user(): User
    {
        $role = Role::firstOrCreate(['slug' => 'passager'], ['nom' => 'Passager']);
        $user = User::create([
            'nom' => 'Test',
            'prenom' => 'Alice',
            'email' => 'alice-' . uniqid() . '@ask.com',
            'telephone' => '69' . substr(uniqid(), -8),
            'password' => Hash::make('password'),
        ]);
        $user->roles()->attach($role);

        return $user;
    }

    public function test_hors_domaine_refus_sans_appel_reseau(): void
    {
        $user = $this->user();

        $response = $this->actingAs($user)->postJson('/api/v1/ai/ask', [
            'question' => 'Quelle est la capitale de l\'Australie ?',
        ]);

        $response->assertOk()
            ->assertJsonPath('hors_domaine', true)
            ->assertJsonPath('reponse', AiService::HORS_DOMAINE_REPONSE)
            ->assertJsonPath('generateur', 'REGLE');
    }

    public function test_question_plateforme_recoit_une_reponse(): void
    {
        $user = $this->user();

        $response = $this->actingAs($user)->postJson('/api/v1/ai/ask', [
            'question' => 'Comment réserver un trajet ?',
        ]);

        $response->assertOk()
            ->assertJsonPath('hors_domaine', false)
            ->assertJsonStructure(['reponse', 'hors_domaine', 'generateur']);
        $this->assertNotSame(AiService::HORS_DOMAINE_REPONSE, $response->json('reponse'));
    }

    public function test_question_qr_repond_le_qr(): void
    {
        $user = $this->user();

        $response = $this->actingAs($user)->postJson('/api/v1/ai/ask', [
            'question' => 'Comment fonctionne le QR de vérification ?',
        ]);

        $response->assertOk()->assertJsonPath('hors_domaine', false);
        $this->assertStringContainsStringIgnoringCase('QR', $response->json('reponse'));
    }

    public function test_validation_question_requise(): void
    {
        $user = $this->user();

        $this->actingAs($user)->postJson('/api/v1/ai/ask', ['question' => ''])
            ->assertStatus(422);
    }

    public function test_auth_requise(): void
    {
        $this->postJson('/api/v1/ai/ask', ['question' => 'test'])
            ->assertUnauthorized();
    }

    public function test_ia_activee_refus_llm_normalise(): void
    {
        config([
            'services.ai.enabled' => true,
            'services.ai.api_key' => 'sk-test',
            'services.ai.base_url' => 'https://ai.test/v1',
            'services.ai.model' => 'test-model',
        ]);

        Http::fake([
            'ai.test/*' => Http::response([
                'choices' => [['message' => ['content' => 'Cette question n\'est pas dans mes compétences. Je réponds uniquement aux questions liées à SafeRide : trajets, réservations, sécurité (SOS, QR), profil, prédiction de trafic…']]],
            ], 200),
        ]);

        $user = $this->user();
        // « itineraire » passe le pré-filtre -> appel LLM -> refus normalisé.
        $response = $this->actingAs($user)->postJson('/api/v1/ai/ask', [
            'question' => 'Trace-moi un itinéraire vers Paris',
        ]);

        $response->assertOk()
            ->assertJsonPath('hors_domaine', true)
            ->assertJsonPath('reponse', AiService::HORS_DOMAINE_REPONSE)
            ->assertJsonPath('generateur', 'IA_SafeRide');
        Http::assertSentCount(1);
    }
}
