<?php

namespace Tests\Feature;

use App\Models\Role;
use App\Models\SosAlert;
use App\Models\Trip;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

/**
 * Le scan du QR transporteur doit exposer ses stats de transport au passager :
 * trajets réalisés, alertes SOS des passagers pendant ses courses, photo, avis.
 */
class TripScanStatsTest extends TestCase
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

    private function scan(): array
    {
        Http::fake(['*' => Http::response('', 500)]);
        $transporteur = $this->user('t-stats@coverage.com', '690000030', 'transporteur');
        $passager = $this->user('p-stats@coverage.com', '690000031', 'passager');

        $vehicle = $this->actingAs($transporteur)->postJson('/api/v1/vehicles', [
            'marque' => 'Toyota',
            'modele' => 'Corolla',
            'immatriculation' => 'LT-STAT-AB',
            'type' => 'VOITURE',
        ])->assertCreated()->json('vehicle');

        $this->actingAs($transporteur)->postJson("/api/v1/vehicles/{$vehicle['id']}/position", [
            'latitude' => 3.8480,
            'longitude' => 11.5021,
        ])->assertOk();

        // Une première course TERMINÉE du transporteur avec une alerte SOS passager,
        // pour vérifier les agrégats (trips_count + sos_count) réellement en base.
        $t1 = Trip::create([
            'passager_id' => $passager->id,
            'transporteur_id' => $transporteur->id,
            'vehicle_id' => $vehicle['id'],
            'start_latitude' => 3.8480,
            'start_longitude' => 11.5021,
            'started_at' => now()->subHours(5),
            'ended_at' => now()->subHours(4),
            'statut' => 'TERMINE',
            'distance_km' => 7.5,
        ]);
        SosAlert::create([
            'trip_id' => $t1->id,
            'passager_id' => $passager->id,
            'declenchement' => 'BOUTON',
            'latitude' => 3.8600,
            'longitude' => 11.5100,
            'heure_detection' => now()->subHours(4),
            'statut' => 'RESOLU',
        ]);

        $response = $this->actingAs($passager)->postJson('/api/v1/trips/start', [
            'token' => $vehicle['qr_codes'][0]['token'],
            'latitude' => 3.8480,
            'longitude' => 11.5021,
        ])->assertCreated();

        return [$transporteur, $response->json('transporteur') ?? []];
    }

    public function test_scan_exposes_transporteur_photo_rating_and_reviews(): void
    {
        [$transporteur, $data] = $this->scan();

        $this->assertEquals($transporteur->id, $data['id']);
        $this->assertEquals('User', $data['prenom']);
        $this->assertArrayHasKey('photo_url', $data);
        $this->assertArrayHasKey('average_rating', $data);
        $this->assertArrayHasKey('ratings_count', $data);
        $this->assertArrayHasKey('reviews', $data);
        $this->assertIsArray($data['reviews']);
    }

    public function test_scan_counts_completed_trips_and_passenger_sos_alerts(): void
    {
        [, $data] = $this->scan();

        // 1 course TERMINÉE + 1 en cours (SCANNE) → trips_count = 1
        $this->assertSame(1, $data['trips_count']);

        // 1 alerte SOS de passager déclenchée pendant ses courses
        $this->assertSame(1, $data['sos_count']);
    }
}