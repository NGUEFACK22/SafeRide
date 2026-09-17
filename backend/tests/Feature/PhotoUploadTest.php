<?php

namespace Tests\Feature;

use App\Models\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class PhotoUploadTest extends TestCase
{
    use RefreshDatabase;

    /** PNG 1x1 valide (détecté `image/png` par fileinfo, sans dépendre de GD). */
    private const PNG_1PX = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

    private function createUser(): User
    {
        $role = Role::firstOrCreate(['slug' => 'passager'], ['nom' => 'Passager']);
        $user = User::create([
            'nom' => 'Test',
            'prenom' => 'User',
            'email' => 'photo-test@saferide.app',
            'telephone' => '699000111',
            'password' => bcrypt('password123'),
            'statut' => 'ACTIF',
        ]);
        $user->roles()->attach($role);

        return $user;
    }

    private function pngFile(int $sizeKb): UploadedFile
    {
        $tmp = sys_get_temp_dir() . '/avatar-test-' . uniqid('', true) . '.png';
        file_put_contents($tmp, base64_decode(self::PNG_1PX));
        if ($sizeKb > 1) {
            // Étendre au-delà de la vraie taille pour tester la limite max:5120 Ko
            // (le fichier reste bien un PNG de tête — fileinfo se base sur le début).
            file_put_contents($tmp, base64_decode(self::PNG_1PX) . str_repeat("\0", max(0, ($sizeKb * 1024) - strlen(base64_decode(self::PNG_1PX)))));
        }

        return new UploadedFile($tmp, 'avatar.png', 'image/png', null, true);
    }

    public function test_upload_photo_stores_file_and_sets_url(): void
    {
        Storage::fake('public');
        $user = $this->createUser();

        $file = $this->pngFile(1);

        $response = $this->actingAs($user)->postJson('/api/v1/auth/profile/photo', [
            'photo' => $file,
        ]);

        $response->assertOk()
            ->assertJsonPath('user.photo_url', fn ($url) => is_string($url) && str_starts_with($url, 'photos/'))
            ->assertJsonPath('user.email', 'photo-test@saferide.app');

        $files = Storage::disk('public')->files('photos');
        $this->assertCount(1, $files);
    }

    public function test_upload_replaces_previous_photo(): void
    {
        Storage::fake('public');
        $user = $this->createUser();
        $user->update(['photo_url' => 'photos/ancienne.png']);
        Storage::disk('public')->put('photos/ancienne.png', base64_decode(self::PNG_1PX));

        $this->actingAs($user)->postJson('/api/v1/auth/profile/photo', [
            'photo' => $this->pngFile(1),
        ])->assertOk();

        Storage::disk('public')->assertMissing('photos/ancienne.png');

        $files = Storage::disk('public')->files('photos');
        $this->assertCount(1, $files);
    }

    public function test_upload_rejects_non_image_file(): void
    {
        Storage::fake('public');
        $user = $this->createUser();

        $tmp = sys_get_temp_dir() . '/document-test-' . uniqid('', true) . '.txt';
        file_put_contents($tmp, 'contenu non-image');

        $file = new UploadedFile($tmp, 'document.txt', 'text/plain', null, true);

        $response = $this->actingAs($user)->postJson('/api/v1/auth/profile/photo', [
            'photo' => $file,
        ]);

        $response->assertStatus(422);
        Storage::disk('public')->assertDirectoryEmpty('photos');
    }

    public function test_upload_rejects_file_exceeding_5mb(): void
    {
        Storage::fake('public');
        $user = $this->createUser();

        $file = $this->pngFile(6000);

        $response = $this->actingAs($user)->postJson('/api/v1/auth/profile/photo', [
            'photo' => $file,
        ]);

        $response->assertStatus(422);
    }

    public function test_unauthenticated_upload_returns_401(): void
    {
        Storage::fake('public');

        $this->postJson('/api/v1/auth/profile/photo', ['photo' => $this->pngFile(1)])
            ->assertStatus(401);
    }
}