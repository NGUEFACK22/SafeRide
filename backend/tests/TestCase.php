<?php

namespace Tests;

use App\Models\IdentityVerification;
use App\Models\User;
use Illuminate\Foundation\Testing\TestCase as BaseTestCase;

abstract class TestCase extends BaseTestCase
{
    /**
     * Marque un utilisateur comme identité KYC vérifiée (statut VERIFIE),
     * requis pour créer/lancer des courses (gates passager + transporteur).
     */
    protected function verifyIdentity(User $user): User
    {
        IdentityVerification::create([
            'user_id' => $user->id,
            'type' => 'CNI',
            'statut' => 'VERIFIE',
            'verifie_le' => now(),
        ]);

        return $user;
    }
}
