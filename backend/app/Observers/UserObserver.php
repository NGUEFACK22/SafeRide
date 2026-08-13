<?php

namespace App\Observers;

use App\Models\AuditLog;
use App\Models\User;
use Illuminate\Support\Facades\Request;

class UserObserver
{
    public function created(User $user): void
    {
        AuditLog::create([
            'user_id' => $user->id,
            'action' => 'user_registered',
            'entity_type' => 'User',
            'entity_id' => $user->id,
            'details' => [
                'email' => $user->email,
                'telephone' => $user->telephone,
                'statut' => $user->statut,
            ],
            'ip' => Request::ip(),
            'user_agent' => Request::userAgent(),
        ]);
    }
}
