<?php

namespace Tests\Feature;

use App\Models\EmergencyContact;
use App\Models\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class EmergencyContactTest extends TestCase
{
    use RefreshDatabase;

    private function passager(string $email = 'passager@example.com', string $telephone = '690000070'): User
    {
        $role = Role::firstOrCreate(['slug' => 'passager'], ['nom' => 'Passager']);
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

    public function test_user_adds_emergency_contact(): void
    {
        $user = $this->passager();
        $this->actingAs($user);

        $this->postJson('/api/v1/emergency-contacts', [
            'nom' => 'Mère',
            'telephone' => '690000071',
            'relation' => 'Mère',
            'email' => 'mere@example.com',
        ])->assertCreated();

        $this->assertDatabaseHas('emergency_contacts', [
            'user_id' => $user->id,
            'nom' => 'Mère',
            'telephone' => '690000071',
        ]);
    }

    public function test_contacts_list_is_scoped_to_own_user(): void
    {
        $user = $this->passager();
        $other = $this->passager('other@example.com', '690000072');
        $this->actingAs($user);

        EmergencyContact::create([
            'user_id' => $user->id,
            'nom' => 'Frère',
            'telephone' => '690000073',
        ]);
        EmergencyContact::create([
            'user_id' => $other->id,
            'nom' => 'Autre',
            'telephone' => '690000074',
        ]);

        $json = $this->getJson('/api/v1/emergency-contacts')->assertOk()->json('contacts');
        $contacts = isset($json['data']) ? $json['data'] : $json;
        $this->assertCount(1, $contacts);
        $this->assertEquals('Frère', $contacts[0]['nom']);
    }

    public function test_user_updates_own_contact(): void
    {
        $user = $this->passager();
        $this->actingAs($user);

        $contact = EmergencyContact::create([
            'user_id' => $user->id,
            'nom' => 'Mère',
            'telephone' => '690000075',
        ]);

        $this->putJson("/api/v1/emergency-contacts/{$contact->id}", [
            'telephone' => '690000076',
            'email' => 'maman@example.com',
        ])->assertOk();

        $this->assertDatabaseHas('emergency_contacts', [
            'id' => $contact->id,
            'telephone' => '690000076',
            'email' => 'maman@example.com',
        ]);
    }

    public function test_user_cannot_touch_another_users_contact(): void
    {
        $user = $this->passager();
        $other = $this->passager('other2@example.com', '690000077');
        $contact = EmergencyContact::create([
            'user_id' => $other->id,
            'nom' => 'Autre',
            'telephone' => '690000078',
        ]);

        $this->actingAs($user);
        $this->putJson("/api/v1/emergency-contacts/{$contact->id}", ['nom' => 'Hack'])
            ->assertNotFound();
        $this->deleteJson("/api/v1/emergency-contacts/{$contact->id}")
            ->assertNotFound();
    }

    public function test_user_deletes_own_contact(): void
    {
        $user = $this->passager();
        $this->actingAs($user);

        $contact = EmergencyContact::create([
            'user_id' => $user->id,
            'nom' => 'Mère',
            'telephone' => '690000079',
        ]);

        $this->deleteJson("/api/v1/emergency-contacts/{$contact->id}")->assertOk();
        $this->assertDatabaseMissing('emergency_contacts', ['id' => $contact->id]);
    }
}