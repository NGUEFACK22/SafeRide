<?php

namespace Tests\Feature;

use App\Models\Notification;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class NotificationTest extends TestCase
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

    public function test_notifications_require_authentication(): void
    {
        $this->getJson('/api/v1/notifications')->assertStatus(401);
    }

    public function test_index_returns_only_own_notifications_and_unread_count(): void
    {
        $me = $this->user('me@example.com', '690000001');
        $other = $this->user('other@example.com', '690000002');

        Notification::create(['user_id' => $me->id, 'type' => 'SOS', 'titre' => 'SOS', 'message' => 'm1']);
        Notification::create(['user_id' => $me->id, 'type' => 'DOSSIER', 'titre' => 'Dossier', 'message' => 'm2', 'lu' => true]);
        Notification::create(['user_id' => $other->id, 'type' => 'SOS', 'titre' => 'Autre', 'message' => 'm3']);

        $token = $me->createToken('test')->plainTextToken;

        $this->withToken($token)
            ->getJson('/api/v1/notifications')
            ->assertStatus(200)
            ->assertJsonCount(2, 'notifications')
            ->assertJsonPath('unread_count', 1);
    }

    public function test_unread_count_endpoint(): void
    {
        $me = $this->user('me@example.com', '690000003');
        Notification::create(['user_id' => $me->id, 'type' => 'SYSTEME', 'titre' => 'A', 'message' => 'm']);

        $token = $me->createToken('test')->plainTextToken;

        $this->withToken($token)
            ->getJson('/api/v1/notifications/unread-count')
            ->assertStatus(200)
            ->assertJsonPath('unread_count', 1);
    }

    public function test_mark_read_updates_lu(): void
    {
        $me = $this->user('me@example.com', '690000004');
        $notif = Notification::create(['user_id' => $me->id, 'type' => 'SYSTEME', 'titre' => 'A', 'message' => 'm']);

        $token = $me->createToken('test')->plainTextToken;

        $this->withToken($token)
            ->postJson("/api/v1/notifications/{$notif->id}/read")
            ->assertStatus(200);

        $this->assertDatabaseHas('notifications', ['id' => $notif->id, 'lu' => true]);
    }

    public function test_cannot_mark_read_someone_elses_notification(): void
    {
        $me = $this->user('me@example.com', '690000005');
        $other = $this->user('other@example.com', '690000006');
        $notif = Notification::create(['user_id' => $other->id, 'type' => 'SYSTEME', 'titre' => 'A', 'message' => 'm']);

        $token = $me->createToken('test')->plainTextToken;

        $this->withToken($token)
            ->postJson("/api/v1/notifications/{$notif->id}/read")
            ->assertStatus(404);
    }
}
