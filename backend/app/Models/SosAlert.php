<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class SosAlert extends Model
{
    use HasFactory;

    protected $fillable = [
        'trip_id',
        'passager_id',
        'declenchement',
        'latitude',
        'longitude',
        'heure_detection',
        'statut',
        'details',
    ];

    protected function casts(): array
    {
        return [
            'heure_detection' => 'datetime',
            'latitude' => 'decimal:7',
            'longitude' => 'decimal:7',
            'details' => 'array',
        ];
    }

    public function trip(): BelongsTo
    {
        return $this->belongsTo(Trip::class);
    }

    public function passager(): BelongsTo
    {
        return $this->belongsTo(User::class, 'passager_id');
    }

    public function emergencyNotifications(): HasMany
    {
        return $this->hasMany(SosEmergencyNotification::class);
    }
}