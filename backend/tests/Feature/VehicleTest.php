<?php

namespace Tests\Feature;

use App\Models\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class VehicleTest extends TestCase
{
    use RefreshDatabase;

    private function transporteur(string $email = 'transporteur@example.com', string $telephone = '690000030'): User
    {
        $role = Role::firstOrCreate(['slug' => 'transporteur'], ['nom' => 'Transporteur']);
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

    public function test_transporteur_creates_vehicle_with_signed_qr(): void
    {
        $transporteur = $this->transporteur();
        $this->actingAs($transporteur);

        $response = $this->postJson('/api/v1/vehicles', [
            'marque' => 'Honda',
            'modele' => 'PCX',
            'immatriculation' => 'LT-888-ZZ',
            'type' => 'MOTO',
            'couleur' => 'Noir',
        ])->assertCreated();

        $vehicle = $response->json('vehicle');
        $this->assertEquals($transporteur->id, $vehicle['transporteur_id']);
        $this->assertNotEmpty($vehicle['qr_codes'][0]['token'] ?? null);
        $this->assertTrue($vehicle['qr_codes'][0]['actif']);
    }

    public function test_transporteur_lists_only_own_vehicles(): void
    {
        $transporteur = $this->transporteur('t1@example.com', '690000031');
        $other = $this->transporteur('t2@example.com', '690000032');

        $this->actingAs($transporteur)->postJson('/api/v1/vehicles', [
            'marque' => 'Toyota',
            'modele' => 'Yaris',
            'immatriculation' => 'LT-111-AA',
            'type' => 'VOITURE',
        ])->assertCreated();

        $this->actingAs($other)->postJson('/api/v1/vehicles', [
            'marque' => 'Renault',
            'modele' => 'Clio',
            'immatriculation' => 'LT-222-BB',
            'type' => 'VOITURE',
        ])->assertCreated();

        $this->actingAs($transporteur);
        $vehicles = $this->getJson('/api/v1/vehicles')->assertOk()->json('vehicles');
        $this->assertCount(1, $vehicles);
        $this->assertEquals('LT-111-AA', $vehicles[0]['immatriculation']);
    }

    public function test_qr_code_can_be_toggled(): void
    {
        $transporteur = $this->transporteur();
        $this->actingAs($transporteur);

        $vehicle = $this->postJson('/api/v1/vehicles', [
            'marque' => 'Toyota',
            'modele' => 'Corolla',
            'immatriculation' => 'LT-333-CC',
            'type' => 'VOITURE',
        ])->assertCreated()->json('vehicle');

        $qr = $vehicle['qr_codes'][0];

        // Désactivation.
        $this->postJson("/api/v1/vehicles/{$vehicle['id']}/qr/toggle", ['actif' => false])
            ->assertOk();
        $this->assertDatabaseHas('qr_codes', ['id' => $qr['id'], 'actif' => false]);

        // Réactivation.
        $this->postJson("/api/v1/vehicles/{$vehicle['id']}/qr/toggle", ['actif' => true])
            ->assertOk();
        $this->assertDatabaseHas('qr_codes', ['id' => $qr['id'], 'actif' => true]);
    }
}