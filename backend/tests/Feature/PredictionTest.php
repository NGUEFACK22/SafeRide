<?php

namespace Tests\Feature;

use App\Models\Role;
use App\Models\Trip;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

/**
 * Endpoint PRÉDICTION : analyse l'historique de l'utilisateur (zones
 * fréquentes, densité horaire), interroge Open-Meteo pour le climat et
 * renvoie heures de bouchons + conseils.
 */
class PredictionTest extends TestCase
{
    use RefreshDatabase;

    private function passengerWithTrips(): User
    {
        $role = Role::firstOrCreate(['slug' => 'passager'], ['nom' => 'Passager']);
        $user = User::create([
            'nom' => 'Mbarga',
            'prenom' => 'Paul',
            'email' => 'paul-' . uniqid() . '@pred.com',
            'telephone' => '67' . substr(uniqid(), -8),
            'password' => Hash::make('password'),
        ]);
        $user->roles()->attach($role);

        // Transporteur + véhicule requis par la contrainte NOT NULL des trips.
        $trRole = Role::firstOrCreate(['slug' => 'transporteur'], ['nom' => 'Transporteur']);
        $transporteur = User::create([
            'nom' => 'Talla',
            'prenom' => 'Roger',
            'email' => 'roger-' . uniqid() . '@pred.com',
            'telephone' => '68' . substr(uniqid(), -8),
            'password' => Hash::make('password'),
        ]);
        $transporteur->roles()->attach($trRole);
        $vehicle = \App\Models\Vehicle::create([
            'transporteur_id' => $transporteur->id,
            'marque' => 'Toyota',
            'modele' => 'Corolla',
            'immatriculation' => 'LT-' . mt_rand(10000, 99999) . '-PD',
            'type' => 'VOITURE',
            'statut' => 'ACTIF',
        ]);

        // 6 trajets terminés : zone Bonanjo (4 départs, dont 3 à 8h) + zone
        // Akwa (2 départs à 18h) → pics observés 8h et 18h.
        foreach ([
            [3.8721, 11.5174, 8, 1500], [3.8720, 11.5173, 8, 2100],
            [3.8719, 11.5175, 8, 1800], [3.8722, 11.5172, 9, 1200],
            [3.8620, 11.5240, 18, 2400], [3.8621, 11.5241, 18, 2700],
        ] as $i => [$lat, $lng, $hour, $dur]) {
            $started = now()->subDays($i + 1)->setTime($hour, 10);
            Trip::create([
                'passager_id' => $user->id,
                'transporteur_id' => $transporteur->id,
                'vehicle_id' => $vehicle->id,
                'start_latitude' => $lat,
                'start_longitude' => $lng,
                'destination_latitude' => 3.8480,
                'destination_longitude' => 11.5021,
                'destination_address' => 'Bonabéri',
                'started_at' => $started,
                'ended_at' => $started->copy()->addSeconds($dur),
                'distance_km' => 4.2,
                'duration_seconds' => $dur,
                'statut' => 'TERMINE',
                'end_method' => 'MANUEL',
            ]);
        }

        return $user;
    }

    public function test_prediction_endpoint_returns_climate_hours_and_advice(): void
    {
        config(['services.ai.enabled' => false]);
        $user = $this->passengerWithTrips();

        // Open-Meteo finké : averses, 40 % de pluie.
        Http::fake([
            'api.open-meteo.com/*' => Http::response([
                'current' => [
                    'temperature_2m' => 26.4,
                    'apparent_temperature' => 29.8,
                    'precipitation_probability' => 40,
                    'weather_code' => 80,
                    'wind_speed_10m' => 9.5,
                ],
            ], 200),
        ]);

        $response = $this->actingAs($user)
            ->getJson('/api/v1/ai/prediction')
            ->assertOk()
            ->assertJsonStructure([
                'report' => ['type', 'contenu', 'generateur'],
                'prediction' => [
                    'genere_le',
                    'nb_trajets_analyses',
                    'heures_bouchons',
                    'heures_fluides',
                    'zones_frequentes' => [['libelle', 'trajets', 'latitude', 'longitude']],
                    'climats' => [['zone', 'libelle', 'description', 'temperature_c']],
                    'conseils',
                ],
            ]);

        $response->assertJsonPath('report.type', 'PREDICTION');
        $prediction = $response->json('prediction');

        // 6 trajets analysés.
        $this->assertSame(6, $prediction['nb_trajets_analyses']);

        // Pics : structurels (7,8,17,18) + observés (8h et 18h déjà inclus).
        $this->assertContains('08h00', $prediction['heures_bouchons']);
        $this->assertContains('18h00', $prediction['heures_bouchons']);
        $this->assertContains('17h00', $prediction['heures_bouchons']);

        // Heures fluides proposées et disjointes des pics.
        $this->assertNotEmpty($prediction['heures_fluides']);
        $this->assertEmpty(array_intersect($prediction['heures_bouchons'], $prediction['heures_fluides']));

        // Climat récupéré depuis Open-Meteo (code 80 → Averses).
        $this->assertNotEmpty($prediction['climats']);
        $this->assertSame('Averses', $prediction['climats'][0]['description']);
        $this->assertEquals(26.4, $prediction['climats'][0]['temperature_c']);

        // Zones : nom réel (destination), position et climat rattaché.
        $zones = $prediction['zones_frequentes'];
        $this->assertNotEmpty($zones);
        $this->assertSame('Bonabéri', $zones[0]['libelle']);
        $this->assertEqualsWithDelta(3.8721, (float) $zones[0]['latitude'], 0.001);
        $this->assertEqualsWithDelta(11.5174, (float) $zones[0]['longitude'], 0.001);
        $this->assertSame('Bonabéri', $prediction['climats'][0]['libelle']);
        $this->assertNotNull($prediction['climats'][0]['latitude']);

        // Conseils actionnables présents (mention des heures à éviter).
        $this->assertNotEmpty($prediction['conseils']);
        $joined = implode(' ', $prediction['conseils']);
        $this->assertStringContainsString('08h', $joined);

        // Repli règle (IA désactivée).
        $this->assertSame('REGLE', $response->json('report.generateur'));
    }

    public function test_frequent_zones_limited_to_two_with_coordinates(): void
    {
        config(['services.ai.enabled' => false]);
        $user = $this->passengerWithTrips();
        Http::fake([
            'api.open-meteo.com/*' => Http::response(['current' => ['temperature_2m' => 25, 'weather_code' => 0, 'precipitation_probability' => 10]], 200),
        ]);

        // 3e cluster (Deido, 2 départs) en plus des 2 du fixture.
        $ref = Trip::where('passager_id', $user->id)->firstOrFail();
        foreach ([[3.8500, 11.5100], [3.8501, 11.5102]] as [$lat, $lng]) {
            Trip::create([
                'passager_id' => $user->id,
                'transporteur_id' => $ref->transporteur_id,
                'vehicle_id' => $ref->vehicle_id,
                'start_latitude' => $lat,
                'start_longitude' => $lng,
                'destination_address' => 'Deido',
                'started_at' => now()->subDay(),
                'ended_at' => now()->subDay()->addHour(),
                'statut' => 'TERMINE',
                'end_method' => 'MANUEL',
            ]);
        }

        $prediction = $this->actingAs($user)
            ->getJson('/api/v1/ai/prediction?refresh=1')
            ->assertOk()
            ->json('prediction');

        // Max 2 zones même avec 3 clusters, triées (Bonanjo 4 en premier).
        $zones = $prediction['zones_frequentes'];
        $this->assertCount(2, $zones);
        $this->assertSame(4, $zones[0]['trajets']);
        foreach ($zones as $z) {
            $this->assertArrayHasKey('latitude', $z);
            $this->assertArrayHasKey('longitude', $z);
            $this->assertNotEmpty($z['libelle']);
        }
        // Climat rattaché à chaque zone affichée.
        $this->assertCount(2, $prediction['climats']);
        foreach ($prediction['climats'] as $c) {
            $this->assertNotEmpty($c['libelle']);
            $this->assertArrayHasKey('latitude', $c);
        }
    }

    public function test_prediction_is_cached_until_refresh(): void
    {
        config(['services.ai.enabled' => false]);
        $user = $this->passengerWithTrips();
        Http::fake(['api.open-meteo.com/*' => Http::response(['current' => ['temperature_2m' => 25, 'weather_code' => 0, 'precipitation_probability' => 10]], 200)]);

        $first = $this->actingAs($user)->getJson('/api/v1/ai/prediction')->assertOk()->json('report.id');
        $second = $this->actingAs($user)->getJson('/api/v1/ai/prediction')->assertOk()->json('report.id');

        // Cache 1 h → même rapport, pas de nouveau AiReport.
        $this->assertSame($first, $second);
        $this->assertSame(1, \App\Models\AiReport::where('user_id', $user->id)->count());

        // ?refresh=1 force une nouvelle génération.
        $third = $this->actingAs($user)->getJson('/api/v1/ai/prediction?refresh=1')->assertOk()->json('report.id');
        $this->assertNotSame($first, $third);
    }

    public function test_prediction_requires_auth(): void
    {
        $this->getJson('/api/v1/ai/prediction')->assertUnauthorized();
    }
}
