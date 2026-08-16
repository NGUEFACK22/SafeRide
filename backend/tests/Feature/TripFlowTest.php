<?php

namespace Tests\Feature;

use App\Models\Role;
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

        // 2. Le passager scanne le QR → SCANNE.
        $start = $this->actingAs($passager)->postJson('/api/v1/trips/start', [
            'token' => $vehicle['qr_codes'][0]['token'],
            'latitude' => 3.8480,
            'longitude' => 11.5021,
        ])->assertCreated()->json('trip');

        $this->assertEquals('SCANNE', $start['statut']);

        // 3. Embarquement confirmé → CONFIRME.
        $confirm = $this->postJson("/api/v1/trips/{$start['id']}/confirm-embarquement")
            ->assertOk()->json('trip');
        $this->assertEquals('CONFIRME', $confirm['statut']);

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
}