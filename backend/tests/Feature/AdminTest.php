<?php

namespace Tests\Feature;

use App\Models\ManagerAssignment;
use App\Models\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class AdminTest extends TestCase
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

    public function test_dashboard_returns_global_stats(): void
    {
        $admin = $this->user('admin@example.com', '690000040', 'admin');
        $this->actingAs($admin);

        $data = $this->getJson('/api/v1/admin/dashboard')->assertOk()->json();

        $this->assertArrayHasKey('users_total', $data);
        $this->assertArrayHasKey('trips_total', $data);
        $this->assertArrayHasKey('sos_total', $data);
        $this->assertArrayHasKey('managers_total', $data);
    }

    public function test_admin_creates_user_with_role(): void
    {
        $admin = $this->user('admin@example.com', '690000041', 'admin');
        Role::firstOrCreate(['slug' => 'transporteur'], ['nom' => 'Transporteur']);
        $this->actingAs($admin);

        $response = $this->postJson('/api/v1/admin/users', [
            'nom' => 'Nouveau',
            'prenom' => 'Compte',
            'email' => 'nouveau@example.com',
            'telephone' => '690000042',
            'password' => 'secret123',
            'role' => 'transporteur',
        ])->assertCreated();

        $this->assertDatabaseHas('users', ['email' => 'nouveau@example.com']);
        $this->assertEquals('transporteur', $response->json('user.roles.0.slug'));
    }

    public function test_admin_lists_and_filters_users(): void
    {
        $admin = $this->user('admin@example.com', '690000043', 'admin');
        $this->actingAs($admin);

        $this->user('passager@example.com', '690000044', 'passager');
        $this->user('transporteur@example.com', '690000045', 'transporteur');

        $all = $this->getJson('/api/v1/admin/users')->assertOk()->json('users.data');
        $this->assertCount(3, $all);

        $filtered = $this->getJson('/api/v1/admin/users?role=transporteur')
            ->assertOk()->json('users.data');
        $this->assertCount(1, $filtered);
        $this->assertEquals('transporteur@example.com', $filtered[0]['email']);
    }

    public function test_admin_toggles_suspension(): void
    {
        $admin = $this->user('admin@example.com', '690000046', 'admin');
        $target = $this->user('passager@example.com', '690000047', 'passager');
        $this->actingAs($admin);

        $this->postJson("/api/v1/admin/users/{$target->id}/toggle-suspension")
            ->assertOk();
        $this->assertDatabaseHas('users', ['id' => $target->id, 'statut' => 'SUSPENDU']);

        $this->postJson("/api/v1/admin/users/{$target->id}/toggle-suspension")
            ->assertOk();
        $this->assertDatabaseHas('users', ['id' => $target->id, 'statut' => 'ACTIF']);
    }

    public function test_manager_stats_returns_resolution_rate(): void
    {
        $admin = $this->user('admin@example.com', '690000048', 'admin');
        $manager = $this->user('manager@example.com', '690000049', 'gestionnaire');
        $this->actingAs($admin);

        ManagerAssignment::create([
            'manager_id' => $manager->id,
            'dossier_type' => 'LITIGE',
            'dossier_id' => 1,
            'statut' => 'CLOTURE',
            'assigned_at' => now(),
            'closed_at' => now(),
        ]);
        ManagerAssignment::create([
            'manager_id' => $manager->id,
            'dossier_type' => 'SOS',
            'dossier_id' => 2,
            'statut' => 'ATTRIBUE',
            'assigned_at' => now(),
        ]);

        $data = $this->getJson('/api/v1/admin/managers/stats')->assertOk()->json('managers');

        $this->assertCount(1, $data);
        $this->assertEquals(2, $data[0]['total']);
        $this->assertEquals(1, $data[0]['résolus']);
        $this->assertEquals(50.0, $data[0]['taux_resolution']);
    }

    public function test_non_admin_cannot_access_admin_routes(): void
    {
        $passager = $this->user('passager@example.com', '690000050', 'passager');
        $this->actingAs($passager);

        $this->getJson('/api/v1/admin/dashboard')->assertForbidden();
        $this->getJson('/api/v1/admin/users')->assertForbidden();
    }
}