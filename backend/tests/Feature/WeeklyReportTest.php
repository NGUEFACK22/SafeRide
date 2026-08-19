<?php

namespace Tests\Feature;

use App\Console\Commands\GenerateWeeklyReports;
use App\Models\AiReport;
use App\Models\Trip;
use App\Models\User;
use App\Models\Vehicle;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class WeeklyReportTest extends TestCase
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

    private function finishedTrip(User $user): Trip
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
            'statut' => 'TERMINE',
            'start_latitude' => 3.8480,
            'start_longitude' => 11.5021,
            'started_at' => now()->subDay(),
            'ended_at' => now(),
            'distance_km' => 12.5,
            'duration_seconds' => 1800,
            'end_method' => 'MANUEL',
        ]);
    }

    public function test_weekly_endpoint_generates_report_with_trip_data(): void
    {
        // Repli déterministe (pas d'appel réel à Mistral)
        config(['services.ai.enabled' => false]);

        $user = $this->user();
        $this->actingAs($user);
        $this->finishedTrip($user);

        $response = $this->getJson('/api/v1/ai/weekly')->assertOk();

        $report = $response->json('report');
        $this->assertEquals('RAPPORT_HEBDOMADAIRE', $report['type']);
        $this->assertStringContainsString('trajets_effectues : 1', $report['contenu']);

        $this->assertDatabaseHas('ai_reports', [
            'user_id' => $user->id,
            'type' => 'RAPPORT_HEBDOMADAIRE',
        ]);
    }

    public function test_weekly_endpoint_reuses_report_of_current_week(): void
    {
        config(['services.ai.enabled' => false]);

        $user = $this->user();
        $this->actingAs($user);

        $first = $this->getJson('/api/v1/ai/weekly')->assertOk()->json('report');
        $second = $this->getJson('/api/v1/ai/weekly')->assertOk()->json('report');

        $this->assertEquals($first['id'], $second['id']);
        $this->assertEquals(1, AiReport::where('user_id', $user->id)
            ->where('type', 'RAPPORT_HEBDOMADAIRE')->count());
    }

    public function test_weekly_refresh_forces_regeneration(): void
    {
        config(['services.ai.enabled' => false]);

        $user = $this->user();
        $this->actingAs($user);

        $first = $this->getJson('/api/v1/ai/weekly')->assertOk()->json('report');
        $second = $this->getJson('/api/v1/ai/weekly?refresh=1')->assertOk()->json('report');

        $this->assertNotEquals($first['id'], $second['id']);
    }

    public function test_scheduled_command_generates_reports_for_all_active_users(): void
    {
        config(['services.ai.enabled' => false]);

        $userA = $this->user('a@example.com', '690000011');
        $userB = $this->user('b@example.com', '690000012');

        $this->artisan(GenerateWeeklyReports::class)
            ->expectsOutputToContain('Rapports hebdomadaires générés pour 2 utilisateur(s).')
            ->assertExitCode(0);

        $this->assertEquals(1, AiReport::where('user_id', $userA->id)
            ->where('type', 'RAPPORT_HEBDOMADAIRE')->count());
        $this->assertEquals(1, AiReport::where('user_id', $userB->id)
            ->where('type', 'RAPPORT_HEBDOMADAIRE')->count());
    }
}
