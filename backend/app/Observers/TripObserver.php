<?php

namespace App\Observers;

use App\Models\AuditLog;
use App\Models\Trip;
use Illuminate\Support\Facades\Request;

class TripObserver
{
    protected function log(Trip $trip, string $action, array $details = []): void
    {
        AuditLog::create([
            'user_id' => $trip->passager_id,
            'action' => $action,
            'entity_type' => 'Trip',
            'entity_id' => $trip->id,
            'details' => $details,
            'ip' => Request::ip(),
            'user_agent' => Request::userAgent(),
        ]);
    }

    public function created(Trip $trip): void
    {
        $this->log($trip, 'scan_qr', [
            'vehicle_id' => $trip->vehicle_id,
            'transporteur_id' => $trip->transporteur_id,
            'statut' => $trip->statut,
        ]);
    }

    public function updated(Trip $trip): void
    {
        $from = $trip->getOriginal('statut');
        $to = $trip->statut;

        if ($from === $to) {
            return;
        }

        $map = [
            'SCANNE|CONFIRME' => ['confirm_embarquement', []],
            'CONFIRME|DESTINATION_PROPOSEE' => ['destination_proposee', [
                'destination_address' => $trip->destination_address,
            ]],
            'DESTINATION_PROPOSEE|DESTINATION_CONFIRMEE' => ['destination_confirmee', []],
            'DESTINATION_CONFIRMEE|EN_COURS' => ['trip_start', [
                'destination_address' => $trip->destination_address,
            ]],
            'EN_COURS|TERMINE' => ['trip_end', [
                'distance_km' => $trip->distance_km,
                'duration_seconds' => $trip->duration_seconds,
                'end_method' => $trip->end_method,
            ]],
            'EN_COURS|ANNULE' => ['trip_cancel', []],
        ];

        $key = $from . '|' . $to;
        if (isset($map[$key])) {
            [$action, $details] = $map[$key];
            $this->log($trip, $action, $details);
        }
    }
}
