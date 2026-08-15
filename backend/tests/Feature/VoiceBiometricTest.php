<?php

namespace Tests\Feature;

use App\Models\Trip;
use App\Models\User;
use App\Models\Vehicle;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class VoiceBiometricTest extends TestCase
{
    use RefreshDatabase;

    private function user(string $email = 'passager@example.com', string $telephone = '690000001'): User
    {
        return User::create([
            'nom' => 'Passager',
            'prenom' => 'Test',
            'email' => $email,
            'telephone' => $telephone,
            'password' => Hash::make('password'),
        ]);
    }

    private function embedding(float $offset = 0.0): array
    {
        return array_map(fn ($i) => sin($i * 0.1 + $offset), range(0, 191));
    }

    private function activeTrip(User $user): Trip
    {
        $transporteur = $this->user('transporteur@example.com', '690000002');
        $vehicle = Vehicle::create([
            'transporteur_id' => $transporteur->id,
            'marque' => 'Toyota',
            'modele' => 'Corolla',
            'immatriculation' => 'LT-001-AB',
        ]);

        return Trip::create([
            'passager_id' => $user->id,
            'transporteur_id' => $transporteur->id,
            'vehicle_id' => $vehicle->id,
            'statut' => 'EN_COURS',
            'start_latitude' => 3.8480,
            'start_longitude' => 11.5021,
            'started_at' => now(),
        ]);
    }

    public function test_enroll_embedding_then_voice_sos_uses_cosine_similarity(): void
    {
        $user = $this->user();
        $this->actingAs($user);
        $trip = $this->activeTrip($user);

        $this->postJson('/api/v1/voice/security-word', ['mot_securite' => 'ALERTE'])
            ->assertOk();

        $this->postJson('/api/v1/voice/enroll', ['empreinte' => $this->embedding()])
            ->assertOk();

        $this->assertDatabaseHas('voice_security_profiles', [
            'user_id' => $user->id,
            'actif' => true,
        ]);

        // Même voix (embedding quasi identique) + bon mot-clé → alerte vérifiée.
        $response = $this->postJson('/api/v1/sos', [
            'trip_id' => $trip->id,
            'latitude' => 3.8480,
            'longitude' => 11.5021,
            'declenchement' => 'VOCAL',
            'keyword' => 'ALERTE',
            'empreinte' => $this->embedding(0.001),
        ])->assertCreated();

        $details = $response->json('sos.details');
        $this->assertTrue($details['voiceprint_match']);
        $this->assertTrue($details['verification_passed']);
    }

    public function test_voice_sos_with_different_voice_is_not_verified(): void
    {
        $user = $this->user();
        $this->actingAs($user);
        $trip = $this->activeTrip($user);

        $this->postJson('/api/v1/voice/security-word', ['mot_securite' => 'ALERTE'])
            ->assertOk();
        $this->postJson('/api/v1/voice/enroll', ['empreinte' => $this->embedding()])
            ->assertOk();

        // Autre voix (embedding très différent) → empreinte ne correspond pas.
        $response = $this->postJson('/api/v1/sos', [
            'trip_id' => $trip->id,
            'latitude' => 3.8480,
            'longitude' => 11.5021,
            'declenchement' => 'VOCAL',
            'keyword' => 'ALERTE',
            'empreinte' => $this->embedding(10.0),
        ])->assertCreated();

        $details = $response->json('sos.details');
        $this->assertFalse($details['voiceprint_match']);
        $this->assertFalse($details['verification_passed']);
        $this->assertEquals('VERIFICATION', $response->json('sos.statut'));
    }
}
