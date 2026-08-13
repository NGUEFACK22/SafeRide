<?php

namespace Database\Seeders;

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
    }
}