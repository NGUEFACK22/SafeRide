<?php

namespace Database\Seeders;

use App\Models\Dispute;
use App\Models\LostItemReport;
use App\Models\ManagerAssignment;
use App\Models\QrCode;
use App\Models\SosAlert;
use App\Models\Trip;
use App\Models\User;
use App\Models\Vehicle;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Hash;

/**
 * Jeu de données de démonstration pour la soutenance.
 * Crée un scénario réaliste (conducteurs, passagers, trajets, SOS, litiges…)
 * afin que l'assistant IA et les statistiques disposent de données cohérentes.
 *
 * Idempotent : ne s'exécute qu'une seule fois.
 */
class DemoSeeder extends Seeder
{
    private $demoGestionnaire;

    public function run(): void
    {
        if (User::where('email', 'transporteur2@saferide.app')->exists()) {
            $this->command->info('DemoSeeder déjà exécuté, ignoré.');

            return;
        }

        $this->createUsers();
        $this->createTrips();
        $this->createIncidents();
        $this->createManagerAssignments();

        $this->command->info('Données de démonstration créées avec succès.');
    }

    private function createUsers(): void
    {
        $transporteurs = [
            ['transporteur2@saferide.app', 'Mballa', 'Roger', '690000011'],
            ['transporteur3@saferide.app', 'Foncha', 'Blaise', '690000012'],
        ];
        foreach ($transporteurs as [$email, $nom, $prenom, $tel]) {
            $u = User::create([
                'nom' => $nom,
                'prenom' => $prenom,
                'email' => $email,
                'telephone' => $tel,
                'password' => Hash::make('password'),
                'statut' => 'ACTIF',
            ]);
            $u->assignRole('transporteur');

            $vehicle = Vehicle::create([
                'transporteur_id' => $u->id,
                'marque' => fake()->randomElement(['Toyota', 'Hyundai', 'Kia', 'Honda']),
                'modele' => fake()->word(),
                'immatriculation' => 'LT-'.fake()->unique()->numerify('####').fake()->randomLetter(),
                'type' => fake()->randomElement(['VOITURE', 'MOTO']),
                'couleur' => fake()->safeColorName(),
                'statut' => 'ACTIF',
                'last_latitude' => 3.8480 + fake()->randomFloat(4, -0.05, 0.05),
                'last_longitude' => 11.5021 + fake()->randomFloat(4, -0.05, 0.05),
                'last_position_at' => now()->subMinutes(fake()->numberBetween(1, 30)),
            ]);
            QrCode::create([
                'vehicle_id' => $vehicle->id,
                'token' => bin2hex(random_bytes(16)),
                'actif' => true,
            ]);
        }

        $passagers = [
            ['passager2@saferide.app', 'Atangana', 'Sandra', '690000021'],
            ['passager3@saferide.app', 'Biya', 'Éric', '690000022'],
            ['passager4@saferide.app', 'Manga', 'Lucie', '690000023'],
        ];
        foreach ($passagers as [$email, $nom, $prenom, $tel]) {
            $u = User::create([
                'nom' => $nom,
                'prenom' => $prenom,
                'email' => $email,
                'telephone' => $tel,
                'password' => Hash::make('password'),
                'statut' => 'ACTIF',
            ]);
            $u->assignRole('passager');
        }
    }

    private function createTrips(): void
    {
        $transporteurs = User::whereHas('roles', fn ($q) => $q->where('slug', 'transporteur'))->get();
        $passagers = User::whereHas('roles', fn ($q) => $q->where('slug', 'passager'))->get();
        $vehicles = Vehicle::all();

        $scenarios = [
            // trajet normal terminé
            ['TERMINE', 12.4, 940, 0.1, false, -2],
            // trajet avec déviation importante (anomalie)
            ['TERMINE', 8.1, 720, 1.4, true, -1],
            // trajet court terminé
            ['TERMINE', 4.2, 360, 0.0, false, -3],
            // trajet en cours
            ['EN_COURS', null, null, null, false, 0],
        ];

        foreach ($scenarios as $i => [$statut, $distance, $duree, $deviation, $alert, $daysOffset]) {
            $transporteur = $transporteurs[$i % $transporteurs->count()];
            $passager = $passagers[$i % $passagers->count()];
            $vehicle = $vehicles->firstWhere('transporteur_id', $transporteur->id) ?? $vehicles->first();

            $started = now()->addDays($daysOffset)->setTime(9 + $i, 0, 0);
            $trip = Trip::create([
                'passager_id' => $passager->id,
                'transporteur_id' => $transporteur->id,
                'vehicle_id' => $vehicle->id,
                'qr_token' => bin2hex(random_bytes(8)),
                'start_latitude' => 3.8480,
                'start_longitude' => 11.5021,
                'destination_latitude' => 3.8600,
                'destination_longitude' => 11.5200,
                'destination_address' => fake()->address(),
                'started_at' => $started,
                'ended_at' => $statut === 'TERMINE' ? $started->copy()->addSeconds($duree) : null,
                'distance_km' => $distance,
                'duration_seconds' => $duree,
                'deviation_km' => $deviation,
                'deviation_alert' => $alert,
                'statut' => $statut,
                'end_method' => $statut === 'TERMINE' ? 'MANUEL' : null,
            ]);

            if ($statut === 'TERMINE') {
                $this->seedLocations($trip);
            }
        }
    }

    private function seedLocations(Trip $trip): void
    {
        $baseLat = 3.8480;
        $baseLng = 11.5021;
        for ($j = 0; $j < 5; $j++) {
            $trip->locations()->create([
                'latitude' => $baseLat + ($j * 0.003),
                'longitude' => $baseLng + ($j * 0.004),
                'vitesse_km_h' => fake()->numberBetween(20, 60),
                'captured_at' => $trip->started_at->copy()->addMinutes($j * 3),
            ]);
        }
    }

    private function createIncidents(): void
    {
        $trips = Trip::all();
        $passagers = User::whereHas('roles', fn ($q) => $q->where('slug', 'passager'))->get();
        $transporteurs = User::whereHas('roles', fn ($q) => $q->where('slug', 'transporteur'))->get();
        $gestionnaire = User::whereHas('roles', fn ($q) => $q->where('slug', 'gestionnaire'))->first();

        // SOS vocal en attente de vérification (anomalie active)
        $trip = $trips->first();
        SosAlert::create([
            'trip_id' => $trip->id,
            'passager_id' => $trip->passager_id,
            'declenchement' => 'VOCAL',
            'latitude' => 3.8510,
            'longitude' => 11.5080,
            'heure_detection' => now()->subHour(),
            'statut' => 'VERIFICATION',
            'details' => ['mot_cle_detecte' => 'aide', 'empreinte_valide' => false],
        ]);

        // SOS bouton déclenché et résolu
        $trip2 = $trips->skip(1)->first();
        SosAlert::create([
            'trip_id' => $trip2->id,
            'passager_id' => $trip2->passager_id,
            'declenchement' => 'BOUTON',
            'latitude' => 3.8550,
            'longitude' => 11.5120,
            'heure_detection' => now()->subHours(5),
            'statut' => 'RESOLU',
            'details' => ['empreinte_valide' => null],
        ]);

        // Litige ouvert
        Dispute::create([
            'trip_id' => $trip->id,
            'passager_id' => $trip->passager_id,
            'transporteur_id' => $trip->transporteur_id,
            'motif' => 'Itinéraire non respecté',
            'description' => 'Le conducteur a emprunté un itinéraire différent sans accord.',
            'statut' => 'OUVERT',
        ]);

        // Litige résolu
        Dispute::create([
            'trip_id' => $trip2->id,
            'passager_id' => $trip2->passager_id,
            'transporteur_id' => $trip2->transporteur_id,
            'motif' => 'Montant du tarif contesté',
            'description' => 'Écart de prix par rapport à la confirmation.',
            'decision' => 'Remboursement partiel accordé après vérification.',
            'statut' => 'RESOLU',
        ]);

        // Objet trouvé
        LostItemReport::create([
            'trip_id' => $trip->id,
            'passager_id' => $trip->passager_id,
            'objet' => 'Téléphone portable',
            'description' => 'Smartphone noir oublié à l’arrière du véhicule.',
            'statut' => 'EN_RECHERCHE',
        ]);

        $this->demoGestionnaire = $gestionnaire;
    }

    private function createManagerAssignments(): void
    {
        $gestionnaire = $this->demoGestionnaire ?? User::whereHas('roles', fn ($q) => $q->where('slug', 'gestionnaire'))->first();
        if (! $gestionnaire) {
            return;
        }

        $sos = SosAlert::where('statut', 'VERIFICATION')->first();
        if ($sos) {
            ManagerAssignment::create([
                'manager_id' => $gestionnaire->id,
                'dossier_type' => 'SOS',
                'dossier_id' => $sos->id,
                'statut' => 'PRIS_EN_CHARGE',
                'assigned_at' => now()->subMinutes(30),
                'taken_at' => now()->subMinutes(20),
            ]);
        }

        $dispute = Dispute::where('statut', 'OUVERT')->first();
        if ($dispute) {
            ManagerAssignment::create([
                'manager_id' => $gestionnaire->id,
                'dossier_type' => 'LITIGE',
                'dossier_id' => $dispute->id,
                'statut' => 'ATTRIBUE',
                'assigned_at' => now()->subMinutes(15),
            ]);
        }
    }
}
