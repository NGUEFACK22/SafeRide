<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Vehicle extends Model
{
    use HasFactory;

    protected $fillable = [
        'transporteur_id',
        'marque',
        'modele',
        'immatriculation',
        'type',
        'couleur',
        'statut',
        'last_latitude',
        'last_longitude',
        'last_position_at',
    ];

    protected function casts(): array
    {
        return [
            'last_latitude' => 'decimal:7',
            'last_longitude' => 'decimal:7',
            'last_position_at' => 'datetime',
        ];
    }

    public function transporteur(): BelongsTo
    {
        return $this->belongsTo(User::class, 'transporteur_id');
    }

    public function qrCodes(): HasMany
    {
        return $this->hasMany(QrCode::class);
    }

    public function trips(): HasMany
    {
        return $this->hasMany(Trip::class);
    }
}