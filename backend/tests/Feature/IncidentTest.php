<?php

namespace Tests\Feature;

use App\Models\LostItemReport;
use App\Models\ManagerAssignment;
use App\Models\Role;
use App\Models\Trip;
use App\Models\User;
use App\Models\Vehicle;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class IncidentTest extends TestCase
{
    use RefreshDatabase;

    private User $passager;
    private User $transporteur;
    private User $manager;
    private Vehicle $vehicle;

    protected function setUp(): void
    {
        parent::setUp();

        $this->passager = $this->makeUser('passager@example.com', '690000060', 'passager');
        $this->transporteur = $this->makeUser('transporteur@example.com', '690000061', 'transporteur');
        $this->manager = $this->makeUser('manager@example.com', '690000062', 'gestionnaire');

        $this->vehicle = Vehicle::create([
            'transporteur_id' => $this->transporteur->id,
            'marque' => 'Honda',
            'modele' => 'PCX',
            'immatriculation' => 'LT-777-TT',
        ]);
    }

    private function makeUser(string $email, string $telephone, string $roleSlug): User
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

    private function makeTrip(int $passagerId, ?string $endedAt): Trip
    {
        return Trip::create([
            'passager_id' => $passagerId,
            'transporteur_id' => $this->transporteur->id,
            'vehicle_id' => $this->vehicle->id,
            'start_latitude' => 3.8480,
            'start_longitude' => 11.5021,
            'destination_address' => 'Centre',
            'started_at' => now()->subHours(2),
            'ended_at' => $endedAt,
            'statut' => $endedAt ? 'TERMINE' : 'EN_COURS',
            'end_method' => $endedAt ? 'MANUEL' : null,
        ]);
    }

    public function test_passager_reports_lost_item_and_manager_assigned(): void
    {
        $trip = $this->makeTrip($this->passager->id, now()->subHour());
        $this->actingAs($this->passager);

        $response = $this->postJson('/api/v1/lost-items', [
            'trip_id' => $trip->id,
            'objet' => 'Portefeuille noir',
            'description' => 'Trouvé sur le siège arrière',
        ])->assertCreated();

        $report = $response->json('report');
        $this->assertEquals('SIGNALE', $report['statut']);

        // Un dossier est attribué au gestionnaire + notification.
        $this->assertDatabaseHas('manager_assignments', [
            'manager_id' => $this->manager->id,
            'dossier_type' => 'OBJET_PERDU',
            'dossier_id' => $report['id'],
            'statut' => 'ATTRIBUE',
        ]);
        $this->assertDatabaseHas('notifications', [
            'user_id' => $this->manager->id,
            'type' => 'DOSSIER',
        ]);
    }

    public function test_lost_items_list_is_scoped_to_own_passager(): void
    {
        $other = $this->makeUser('other@example.com', '690000063', 'passager');
        $trip1 = $this->makeTrip($this->passager->id, now()->subHour());
        $trip2 = $this->makeTrip($other->id, now()->subMinutes(30));

        LostItemReport::create(['trip_id' => $trip1->id, 'passager_id' => $this->passager->id, 'objet' => 'Sac']);
        LostItemReport::create(['trip_id' => $trip2->id, 'passager_id' => $other->id, 'objet' => 'Téléphone']);

        $this->actingAs($this->passager);
        $reports = $this->getJson('/api/v1/lost-items')->assertOk()->json('reports.data');

        $this->assertCount(1, $reports);
        $this->assertEquals('Sac', $reports[0]['objet']);
    }

    public function test_chronology_lists_other_passengers_on_same_vehicle(): void
    {
        $other = $this->makeUser('other2@example.com', '690000064', 'passager');
        $trip = $this->makeTrip($this->passager->id, now()->subHour());
        // Autre passager sur le même véhicule, trajet terminé entre la fin et le signalement.
        $otherTrip = $this->makeTrip($other->id, now()->subMinutes(20));

        $report = LostItemReport::create([
            'trip_id' => $trip->id,
            'passager_id' => $this->passager->id,
            'objet' => 'Casque',
        ]);

        $this->actingAs($this->passager);
        $data = $this->getJson("/api/v1/lost-items/{$report->id}/chronology")
            ->assertOk()
            ->json();

        $this->assertEquals($this->vehicle->id, $data['vehicle_id']);
        $this->assertNotEmpty($data['related_trips']);
        $this->assertEquals($otherTrip->id, $data['related_trips'][0]['trip_id']);
    }

    public function test_passager_opens_dispute_and_manager_assigned(): void
    {
        $trip = $this->makeTrip($this->passager->id, now()->subHour());
        $this->actingAs($this->passager);

        $response = $this->postJson('/api/v1/disputes', [
            'trip_id' => $trip->id,
            'motif' => 'Détour d\'itinéraire',
        ])->assertCreated();

        $dispute = $response->json('dispute');
        $this->assertEquals('OUVERT', $dispute['statut']);
        $this->assertEquals($this->passager->id, $dispute['passager_id']);
        $this->assertEquals($this->transporteur->id, $dispute['transporteur_id']);

        $this->assertDatabaseHas('manager_assignments', [
            'manager_id' => $this->manager->id,
            'dossier_type' => 'LITIGE',
            'dossier_id' => $dispute['id'],
        ]);
    }

    public function test_outside_party_cannot_open_dispute(): void
    {
        $trip = $this->makeTrip($this->passager->id, now()->subHour());
        $stranger = $this->makeUser('stranger@example.com', '690000065', 'passager');
        $this->actingAs($stranger);

        $this->postJson('/api/v1/disputes', [
            'trip_id' => $trip->id,
            'motif' => 'Tentative',
        ])->assertForbidden();
    }

    public function test_disputes_list_shows_both_parties(): void
    {
        $trip = $this->makeTrip($this->passager->id, now()->subHour());
        $this->actingAs($this->passager);

        $this->postJson('/api/v1/disputes', [
            'trip_id' => $trip->id,
            'motif' => 'Comportement du chauffeur',
        ])->assertCreated();

        // Le passager voit le litige.
        $passengerList = $this->getJson('/api/v1/disputes')->assertOk()->json('disputes.data');
        $this->assertCount(1, $passengerList);
        $this->assertEquals('Comportement du chauffeur', $passengerList[0]['motif']);

        // Le transporteur (partie) le voit aussi.
        $this->actingAs($this->transporteur);
        $transporteurList = $this->getJson('/api/v1/disputes')->assertOk()->json('disputes.data');
        $this->assertCount(1, $transporteurList);
    }
}