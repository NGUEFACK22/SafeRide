<?php

namespace Tests\Feature;

use App\Models\Trip;
use App\Models\TripLocation;
use App\Models\User;
use App\Models\Vehicle;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class TripRouteTest extends TestCase
{
    use RefreshDatabase;

    private function user(string $email, string $telephone): User
    {
        return User::create([
            'nom' => 'Test',
            'prenom' => 'User',
            'email' => $email,
            'telephone' => $telephone,
            'password' => bcrypt('password123'),
            'statut' => 'ACTIF',
        ]);
    }

    public function test_route_endpoint_returns_decoded_points_for_owner(): void
    {
        $passager = $this->user('passager@example.com', '690000001');
        $transporteur = $this->user('transporteur@example.com', '690000002');

        $vehicle = Vehicle::create([
            'transporteur_id' => $transporteur->id,
            'marque' => 'Yamaha',
            'modele' => 'X',
            'immatriculation' => 'LT-123-AB',
            'type' => 'MOTO',
        ]);

        $trip = Trip::create([
            'passager_id' => $passager->id,
            'transporteur_id' => $transporteur->id,
            'vehicle_id' => $vehicle->id,
            'start_latitude' => 3.8480,
            'start_longitude' => 11.5021,
            'destination_latitude' => 3.8600,
            'destination_longitude' => 11.5200,
            'destination_address' => 'Marche central',
            'started_at' => now()->subMinutes(20),
            'ended_at' => now(),
            'statut' => 'TERMINE',
        ]);

        TripLocation::create([
            'trip_id' => $trip->id,
            'latitude' => 3.8500,
            'longitude' => 11.5050,
            'captured_at' => now()->subMinutes(15),
        ]);
        TripLocation::create([
            'trip_id' => $trip->id,
            'latitude' => 3.8550,
            'longitude' => 11.5100,
            'captured_at' => now()->subMinutes(10),
        ]);

        $token = $passager->createToken('test')->plainTextToken;

        $response = $this->withToken($token)->getJson("/api/v1/trips/{$trip->id}/route");

        $response->assertStatus(200)
            ->assertJsonStructure([
                'trip_id', 'deviation_km', 'deviation_alert', 'start', 'destination', 'points',
            ])
            ->assertJsonCount(4, 'points') // depart + 2 positions + destination
            ->assertJsonPath('start.lat', 3.8480)
            ->assertJsonPath('destination.lng', 11.5200);
    }

    public function test_route_endpoint_forbids_non_owner(): void
    {
        $passager = $this->user('owner@example.com', '690000003');
        $transporteur = $this->user('driver@example.com', '690000004');
        $intruder = $this->user('intruder@example.com', '690000005');

        $vehicle = Vehicle::create([
            'transporteur_id' => $transporteur->id,
            'marque' => 'Yamaha',
            'modele' => 'X',
            'immatriculation' => 'LT-999-ZZ',
            'type' => 'MOTO',
        ]);

        $trip = Trip::create([
            'passager_id' => $passager->id,
            'transporteur_id' => $transporteur->id,
            'vehicle_id' => $vehicle->id,
            'start_latitude' => 3.8480,
            'start_longitude' => 11.5021,
            'started_at' => now()->subMinutes(20),
            'statut' => 'TERMINE',
        ]);

        $token = $intruder->createToken('test')->plainTextToken;

        $this->withToken($token)
            ->getJson("/api/v1/trips/{$trip->id}/route")
            ->assertStatus(403);
    }
}
