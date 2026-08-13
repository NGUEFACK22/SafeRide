<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Trip extends Model
{
    use HasFactory;

    protected $fillable = [
        'passager_id',
        'transporteur_id',
        'vehicle_id',
        'qr_token',
        'start_latitude',
        'start_longitude',
        'destination_latitude',
        'destination_longitude',
        'destination_address',
        'started_at',
        'ended_at',
        'distance_km',
        'duration_seconds',
        'deviation_km',
        'statut',
        'end_method',
    ];

    protected function casts(): array
    {
        return [
            'started_at' => 'datetime',
            'ended_at' => 'datetime',
            'start_latitude' => 'decimal:7',
            'start_longitude' => 'decimal:7',
            'destination_latitude' => 'decimal:7',
            'destination_longitude' => 'decimal:7',
            'distance_km' => 'decimal:2',
            'deviation_km' => 'decimal:2',
        ];
    }

    public function passager(): BelongsTo
    {
        return $this->belongsTo(User::class, 'passager_id');
    }

    public function transporteur(): BelongsTo
    {
        return $this->belongsTo(User::class, 'transporteur_id');
    }

    public function vehicle(): BelongsTo
    {
        return $this->belongsTo(Vehicle::class);
    }

    public function locations(): HasMany
    {
        return $this->hasMany(TripLocation::class);
    }

    public function lostItemReports(): HasMany
    {
        return $this->hasMany(LostItemReport::class);
    }

    public function disputes(): HasMany
    {
        return $this->hasMany(Dispute::class);
    }

    public function sosAlerts(): HasMany
    {
        return $this->hasMany(SosAlert::class);
    }
}