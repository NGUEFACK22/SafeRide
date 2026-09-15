<?php

namespace Database\Seeders;

use App\Models\IdentityVerification;
use App\Models\User;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Hash;

class UsersSeeder extends Seeder
{
    public function run(): void
    {
        $admin = User::firstOrCreate(
            ['email' => 'admin@saferide.app'],
            [
                'nom' => 'Admin',
                'prenom' => 'SafeRide',
                'telephone' => '690000001',
                'password' => Hash::make('password'),
                'statut' => 'ACTIF',
            ]
        );
        $admin->assignRole('admin');

        $gestionnaire = User::firstOrCreate(
            ['email' => 'gestionnaire@saferide.app'],
            [
                'nom' => 'Gestionnaire',
                'prenom' => 'SafeRide',
                'telephone' => '690000002',
                'password' => Hash::make('password'),
                'statut' => 'ACTIF',
            ]
        );
        $gestionnaire->assignRole('gestionnaire');

        $transporteur = User::firstOrCreate(
            ['email' => 'transporteur@saferide.app'],
            [
                'nom' => 'Dupont',
                'prenom' => 'Jean',
                'telephone' => '690000003',
                'password' => Hash::make('password'),
                'statut' => 'ACTIF',
            ]
        );
        $transporteur->assignRole('transporteur');

        $passager = User::firstOrCreate(
            ['email' => 'passager@saferide.app'],
            [
                'nom' => 'Ndiaye',
                'prenom' => 'Karim',
                'telephone' => '690000004',
                'password' => Hash::make('password'),
                'statut' => 'ACTIF',
            ]
        );
        $passager->assignRole('passager');

        // Comptes système de démonstration : identité marquée « VÉRIFIÉE » pour
        // que le badge du profil (mobile : /identity/status) et les écrans
        // gestionnaire/admin affichent la pastille verte « IDENTITÉ VÉRIFIÉE ».
        foreach ([$admin, $gestionnaire, $transporteur, $passager] as $u) {
            if (! IdentityVerification::where('user_id', $u->id)->exists()) {
                IdentityVerification::create([
                    'user_id' => $u->id,
                    'type' => 'CNI',
                    'statut' => 'VERIFIE',
                    'provider_kyc' => 'seed',
                    'verifie_le' => now(),
                ]);
            }
            // Email vérifié également (plus de relance de vérification possible).
            if (! $u->hasVerifiedEmail()) {
                $u->markEmailAsVerified();
            }
        }
    }
}