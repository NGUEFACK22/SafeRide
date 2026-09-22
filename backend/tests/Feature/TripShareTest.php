<?php

namespace Tests\Feature;

use App\Models\Role;
use App\Models\SosAlert;
use App\Models\Trip;
use App\Models\User;
use App\Models\Vehicle;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

/**
 * Suivi GPS public par lien partageable (/api/v1/public/suivi/{token}).
 */
class TripShareTest extends TestCase
{
    use RefreshDatabase;

    private function passager(): User
    {
        return $this->user('passager');
    }

    private function user(string $roleSlug): User
    {
        $role = Role::firstOrCreate(['slug' => $roleSlug], ['nom' => ucfirst($roleSlug)]);
        $user = User::create([
            'nom' => 'Diallo',
            'prenom' => 'Awa',
            'email' => $roleSlug . '-' . uniqid() . '@share.com',
            'telephone' => '69' . substr(uniqid(), -8),
            'password' => Hash::make('password'),
        ]);
        $user->roles()->attach($role);

        return $user;
    }

    private function trip(User $passager, string $statut = 'EN_COURS'): Trip
    {
        $transporteur = $this->user('transporteur');
        $vehicle = Vehicle::create([
            'transporteur_id' => $transporteur->id,
            'marque' => 'Toyota',
            'modele' => 'Corolla',
            'immatriculation' => 'LT-' . substr(uniqid(), -6) . '-SH',
            'type' => 'VOITURE',
        ]);

        $trip = Trip::create([
            'passager_id' => $passager->id,
            'transporteur_id' => $transporteur->id,
            'vehicle_id' => $vehicle->id,
            'start_latitude' => 3.8480,
            'start_longitude' => 11.5021,
            'destination_address' => 'Akwa, Douala',
            'destination_latitude' => 3.8700,
            'destination_longitude' => 11.5210,
            'started_at' => now(),
            'statut' => $statut,
        ]);
        $this->assertNotEmpty($trip->share_token, 'Le share_token doit être créé automatiquement.');

        return $trip;
    }

    public function test_share_token_unique_par_trajet(): void
    {
        $p = $this->passager();
        $t1 = $this->trip($p);
        $t2 = $this->trip($p);
        $this->assertNotSame($t1->share_token, $t2->share_token);
    }

    public function test_page_de_suivi_accessible_sans_authentification(): void
    {
        $trip = $this->trip($this->passager());

        $this->getJson('/api/v1/public/suivi/' . $trip->share_token . '/data')
            ->assertOk()
            ->assertJsonPath('actif', true)
            ->assertJsonPath('destination', 'Akwa, Douala');
    }

    public function test_page_html_rendue_sans_authentification(): void
    {
        $trip = $this->trip($this->passager());

        $this->get('/api/v1/public/suivi/' . $trip->share_token)
            ->assertOk()
            ->assertHeader('Content-Type', 'text/html; charset=UTF-8')
            ->assertSee('Suivi SafeRide en direct', false);
    }

    public function test_token_inconnu_404(): void
    {
        $this->getJson('/api/v1/public/suivi/faux-token-123/data')->assertNotFound();
    }

    public function test_suivi_clos_quand_le_trajet_est_termine(): void
    {
        $trip = $this->trip($this->passager(), 'TERMINE');

        $this->getJson('/api/v1/public/suivi/' . $trip->share_token . '/data')
            ->assertOk()
            ->assertJsonPath('actif', false);
    }

    public function test_position_derniere_gps_renvoyee(): void
    {
        $trip = $this->trip($this->passager());
        $trip->locations()->create([
            'latitude' => 3.8555,
            'longitude' => 11.5111,
            'vitesse_km_h' => 42,
            'captured_at' => now()->subSeconds(20),
        ]);

        $this->getJson('/api/v1/public/suivi/' . $trip->share_token . '/data')
            ->assertOk()
            ->assertJsonPath('position.lat', 3.8555)
            ->assertJsonPath('position.vitesse', 42);
    }

    public function test_partageur_authentifie_recupere_le_lien(): void
    {
        $p = $this->passager();
        $trip = $this->trip($p);

        $res = $this->actingAs($p)->getJson('/api/v1/trips/' . $trip->id . '/share-link')
            ->assertOk()
            ->assertJsonPath('expires_with', 'trip_end');
        $this->assertStringContainsString($trip->share_token, $res->json('url'));
    }

    public function test_heure_sos_affichee_en_heure_locale_douala(): void
    {
        $p = $this->passager();
        $trip = $this->trip($p);
        $sos = SosAlert::create([
            'trip_id' => $trip->id,
            'passager_id' => $p->id,
            'latitude' => 3.85,
            'longitude' => 11.51,
            'declenchement' => 'BOUTON',
            // 10h00 UTC stocké → 11h00 heure de Douala (UTC+1, pas -1h).
            'heure_detection' => '2026-09-21 10:00:00',
            'statut' => 'DECLENCHE',
        ]);

        $data = $sos->forNotification($trip);

        $this->assertEquals('21/09/2026 à 11:00', $data['heure']);
    }

    public function test_position_repliee_sur_sos_sans_points_gps(): void
    {
        $p = $this->passager();
        $trip = $this->trip($p);
        SosAlert::create([
            'trip_id' => $trip->id,
            'passager_id' => $p->id,
            'latitude' => 3.8666,
            'longitude' => 11.5222,
            'declenchement' => 'BOUTON',
            'heure_detection' => now(),
            'statut' => 'DECLENCHE',
        ]);

        // Aucun point GPS de suivi : la position affichée vient du SOS.
        $this->getJson('/api/v1/public/suivi/' . $trip->share_token . '/data')
            ->assertOk()
            ->assertJsonPath('actif', true)
            ->assertJsonPath('position.lat', 3.8666)
            ->assertJsonPath('position.lng', 11.5222);
    }

    public function test_data_inclut_immatriculation_vehicule(): void
    {
        $trip = $this->trip($this->passager());
        $immat = $trip->fresh()->vehicle->immatriculation;

        $this->getJson('/api/v1/public/suivi/' . $trip->share_token . '/data')
            ->assertOk()
            ->assertJsonPath('vehicule', $immat);
    }

    public function test_lien_partage_refuse_aux_tiers(): void
    {
        $trip = $this->trip($this->passager());
        $intrus = $this->passager();

        $this->actingAs($intrus)->getJson('/api/v1/trips/' . $trip->id . '/share-link')
            ->assertNotFound();
    }

    public function test_alerte_sos_en_cours_inclut_le_lien_live(): void
    {
        $p = $this->passager();
        $trip = $this->trip($p);
        $sos = SosAlert::create([
            'trip_id' => $trip->id,
            'passager_id' => $p->id,
            'latitude' => 3.85,
            'longitude' => 11.51,
            'declenchement' => 'ANALYSE_IA',
            'heure_detection' => now(),
            'statut' => 'DECLENCHE',
        ]);

        $data = $sos->forNotification($trip);
        $this->assertStringContainsString($trip->share_token, $data['live_link']);
    }

    public function test_pas_de_lien_live_si_trajet_termine(): void
    {
        $p = $this->passager();
        $trip = $this->trip($p, 'TERMINE');
        $sos = SosAlert::create([
            'trip_id' => $trip->id,
            'passager_id' => $p->id,
            'latitude' => 3.85,
            'longitude' => 11.51,
            'declenchement' => 'BOUTON',
            'heure_detection' => now(),
            'statut' => 'DECLENCHE',
        ]);

        $this->assertSame('—', $sos->forNotification($trip->fresh())['live_link']);
    }

    public function test_mail_sos_affiche_le_lien_suivi_direct(): void
    {
        $p = $this->passager();
        $trip = $this->trip($p);
        $sos = SosAlert::create([
            'trip_id' => $trip->id,
            'passager_id' => $p->id,
            'latitude' => 3.85,
            'longitude' => 11.51,
            'declenchement' => 'BOUTON',
            'heure_detection' => now(),
            'statut' => 'DECLENCHE',
        ]);

        $html = (new \App\Mail\SosAlertMail($sos, $trip, 'Contact'))->render();

        // La ligne "Suivi en direct" doit être PRÉSENTE dans le HTML
        // (régression : elle était construite mais jamais insérée).
        $this->assertStringContainsString('Suivi en direct', $html);
        $this->assertStringContainsString($trip->share_token, $html);
        $this->assertStringContainsString('/public/suivi/', $html);
    }

    public function test_lien_live_regenere_si_share_token_manquant(): void
    {
        $p = $this->passager();
        $trip = $this->trip($p);
        // Simule un trajet créé avant l'introduction du share_token.
        $trip->forceFill(['share_token' => null])->save();

        $sos = SosAlert::create([
            'trip_id' => $trip->id,
            'passager_id' => $p->id,
            'latitude' => 3.85,
            'longitude' => 11.51,
            'declenchement' => 'BOUTON',
            'heure_detection' => now(),
            'statut' => 'DECLENCHE',
        ]);

        $data = $sos->forNotification($trip->fresh());

        $this->assertNotSame('—', $data['live_link']);
        $this->assertNotEmpty($trip->fresh()->share_token);
    }
}
