<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class SosEmergencyNotification extends Model
{
    use HasFactory;

    protected $fillable = [
        'sos_alert_id',
        'emergency_service_id',
        'notifie_le',
        'statut',
    ];

    protected function casts(): array
    {
        return [
            'notifie_le' => 'datetime',
        ];
    }

    public function sosAlert(): BelongsTo
    {
        return $this->belongsTo(SosAlert::class);
    }

    public function emergencyService(): BelongsTo
    {
        return $this->belongsTo(EmergencyService::class);
    }
}