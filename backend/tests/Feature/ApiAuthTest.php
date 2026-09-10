<?php

namespace Tests\Feature;

use App\Models\Role;
use App\Models\SosAlert;
use App\Models\Trip;
use App\Models\TripRating;
use App\Models\User;
use App\Models\Vehicle;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class ApiAuthTest extends TestCase
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
            'password' => bcrypt('password123'),
            'statut' => 'ACTIF',
        ]);
        $user->roles()->attach($role);

        return $user;
    }

    private function trip(User $passager, User $transporteur, Vehicle $vehicle, string $statut, float $distanceKm): Trip
    {
        return Trip::create([
            'passager_id' => $passager->id,
            'transporteur_id' => $transporteur->id,
            'vehicle_id' => $vehicle->id,
            'start_latitude' => 3.8480,
            'start_longitude' => 11.5021,
            'started_at' => now()->subMinutes(30),
            'ended_at' => now(),
            'statut' => $statut,
            'distance_km' => $distanceKm,
        ]);
    }

    /**
     * L'endpoint /auth/profile/stats doit renvoyer des agrégats exacts en base :
     * comptage sans pagination, vraie moyenne des notes reçues (pondérée par
     * note, pas par trajet) et SOS réellement enregistrés — pas le compteur
     * local du téléphone.
     */
    public function test_profile_stats_returns_exact_aggregates(): void
    {
        $passager = $this->user('passager@example.com', '690000001', 'passager');
        $transporteur = $this->user('transporteur@example.com', '690000002', 'transporteur');

        $vehicle = Vehicle::create([
            'transporteur_id' => $transporteur->id,
            'marque' => 'Toyota',
            'modele' => 'Corolla',
            'immatriculation' => 'LT-999-AB',
            'type' => 'VOITURE',
        ]);

        // 2 trajets TERMINÉS du passager (comptés).
        $t1 = $this->trip($passager, $transporteur, $vehicle, 'TERMINE', 5.5);
        $this->trip($passager, $transporteur, $vehicle, 'TERMINE', 3.5);

        // Hors champ : trajet TERMINÉ d'un autre passager + trajet non terminé.
        $other = $this->user('other@example.com', '690000003', 'passager');
        $this->trip($other, $transporteur, $vehicle, 'TERMINE', 50);
        $this->trip($passager, $transporteur, $vehicle, 'EN_COURS', 99);

        // Notes REÇUES par le passager : 3, 5, 5 → vraie moyenne (3+5+5)/3 = 4.33
        // (une moyenne de moyennes par trajet donnerait (3+5)/2 = 4.0).
        $rater1 = $this->user('rater1@example.com', '690000004', 'passager');
        $rater2 = $this->user('rater2@example.com', '690000005', 'passager');
        $rater3 = $this->user('rater3@example.com', '690000006', 'passager');
        TripRating::create(['trip_id' => $t1->id, 'rater_id' => $rater1->id, 'rated_id' => $passager->id, 'rating' => 3]);
        TripRating::create(['trip_id' => $t1->id, 'rater_id' => $rater3->id, 'rated_id' => $passager->id, 'rating' => 5]);
        TripRating::create(['trip_id' => $t1->id, 'rater_id' => $rater2->id, 'rated_id' => $passager->id, 'rating' => 5]);

        // 1 SOS réellement enregistré en base pour le passager.
        SosAlert::create([
            'trip_id' => $t1->id,
            'passager_id' => $passager->id,
            'declenchement' => 'BOUTON',
            'latitude' => 3.8480,
            'longitude' => 11.5021,
            'heure_detection' => now(),
            'statut' => 'DECLENCHE',
        ]);

        $response = $this->actingAs($passager)->getJson('/api/v1/auth/profile/stats')->assertOk();
        $stats = $response->json('stats');

        $this->assertEquals(2, $stats['trips_count']);
        $this->assertSame(9.0, (float) $stats['total_km']);
        $this->assertSame(4.33, (float) $stats['rating_avg']);
        $this->assertEquals(3, $stats['ratings_count']);
        $this->assertEquals(1, $stats['sos_count']);

        // Scoping : le transporteur ne voit que SES trajets terminés (3 ici).
        $driverStats = $this->actingAs($transporteur)->getJson('/api/v1/auth/profile/stats')->assertOk()->json('stats');
        $this->assertEquals(3, $driverStats['trips_count']);
    }

    /**
     * Une requête non authentifiée sur une route protégée doit renvoyer 401 JSON,
     * jamais une redirection 500 (route('login') inexistante).
     */
    public function test_unauthenticated_request_returns_401_json(): void
    {
        $response = $this->postJson('/api/v1/identity/submit', [
            'type' => 'CNI',
        ]);

        $response->assertStatus(401)
            ->assertJson(['message' => 'Unauthenticated.']);
    }

    /**
     * Plusieurs routes protégées doivent renvoyer 401 sans token.
     */
    public function test_protected_routes_require_authentication(): void
    {
        $routes = [
            ['GET', '/api/v1/auth/profile'],
            ['GET', '/api/v1/trips/history'],
            ['GET', '/api/v1/ai/summary'],
            ['GET', '/api/v1/identity/status'],
        ];

        foreach ($routes as [$method, $uri]) {
            $this->call($method, $uri)->assertStatus(401);
        }
    }
}
