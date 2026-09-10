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
        'destination',
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

    /**
     * Données structurées prêtes pour une notification (email/SMS/WhatsApp).
     * Utilisé de façon identique par SosAlertMail et SosController.
     */
    public function forNotification(?Trip $trip, string $recipientName = ''): array
    {
        $passager = $this->passager;
        $transporteur = $trip?->transporteur;

        $fullName = fn (?User $u): string => $u
            ? trim($u->prenom . ' ' . $u->nom) ?: '—'
            : '—';

        $startLat = $trip?->start_latitude;
        $startLng = $trip?->start_longitude;
        $departure = ($startLat !== null && $startLat !== '' && $startLng !== null && $startLng !== '')
            ? $startLat . ', ' . $startLng
            : '—';

        $destination = $this->destination ?? $trip?->destination_address ?? '—';
        $hasPos = $this->latitude !== null && $this->longitude !== null
            && $this->latitude !== '' && $this->longitude !== '';

        return [
            'recipient' => $recipientName,
            'passager' => $fullName($passager) !== '—' ? $fullName($passager) : 'Passager SafeRide',
            'transporteur' => $fullName($transporteur),
            'heure' => $this->heure_detection?->format('d/m/Y à H:i') ?? '—',
            'departure' => $departure,
            'destination' => $destination,
            'current_location' => $hasPos ? $this->latitude . ', ' . $this->longitude : '—',
            'maps_link' => $hasPos
                ? 'https://maps.google.com/?q=' . $this->latitude . ',' . $this->longitude
                : '—',
            'trip_id' => $trip?->id !== null ? (string) $trip->id : '—',
        ];
    }
}