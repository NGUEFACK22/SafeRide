<?php

namespace Tests\Feature;

use App\Models\EmergencyContact;
use App\Models\Trip;
use App\Models\User;
use App\Models\Vehicle;
use App\Services\SmsService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class InfobipSmsTest extends TestCase
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

    public function test_sos_sends_sms_to_emergency_contact_with_phone(): void
    {
        $user = $this->user();
        $this->actingAs($user);
        $trip = $this->activeTrip($user);

        EmergencyContact::create([
            'user_id' => $user->id,
            'nom' => 'Maman',
            'telephone' => '+237690000000',
            'email' => 'maman@example.com',
            'relation' => 'Mère',
        ]);

        $sms = $this->mock(SmsService::class);
        $sms->shouldReceive('send')
            ->once()
            ->with('+237690000000', \Mockery::on(fn ($m) => str_contains($m, 'SOS') && str_contains($m, 'Position')))
            ->andReturn(true);

        $response = $this->postJson('/api/v1/sos', [
            'trip_id' => $trip->id,
            'latitude' => 3.8480,
            'longitude' => 11.5021,
            'declenchement' => 'BOUTON',
        ])->assertCreated();

        $this->assertEquals('NOTIFIE', $response->json('sos.statut'));
        $this->assertDatabaseHas('notifications', [
            'user_id' => $user->id,
            'type' => 'SOS',
        ]);
    }

    public function test_sos_without_africastalking_config_does_not_fail(): void
    {
        $user = $this->user();
        $this->actingAs($user);
        $trip = $this->activeTrip($user);

        EmergencyContact::create([
            'user_id' => $user->id,
            'nom' => 'Papa',
            'telephone' => '690000001',
        ]);

        // Pas de mock : SmsService sans config doit retomber silencieusement.
        $response = $this->postJson('/api/v1/sos', [
            'trip_id' => $trip->id,
            'latitude' => 3.8480,
            'longitude' => 11.5021,
            'declenchement' => 'BOUTON',
        ])->assertCreated();

        $this->assertEquals('NOTIFIE', $response->json('sos.statut'));
    }
}
