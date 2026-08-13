<?php

namespace App\Observers;

use App\Models\AuditLog;
use App\Models\SosAlert;
use Illuminate\Support\Facades\Request;

class SosAlertObserver
{
    public function created(SosAlert $alert): void
    {
        AuditLog::create([
            'user_id' => $alert->passager_id,
            'action' => 'sos_declenche',
            'entity_type' => 'SosAlert',
            'entity_id' => $alert->id,
            'details' => [
                'declenchement' => $alert->declenchement,
                'trip_id' => $alert->trip_id,
                'latitude' => $alert->latitude,
                'longitude' => $alert->longitude,
                'statut' => $alert->statut,
            ],
            'ip' => Request::ip(),
            'user_agent' => Request::userAgent(),
        ]);
    }
}
