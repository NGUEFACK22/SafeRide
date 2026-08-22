<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Laravel\Sanctum\HasApiTokens;

class User extends Authenticatable
{
    use HasApiTokens, HasFactory, Notifiable;

    protected $fillable = [
        'nom',
        'prenom',
        'email',
        'telephone',
        'password',
        'photo_url',
        'statut',
        'google_id',
        'email_verified_at',
    ];

    protected $hidden = [
        'password',
        'remember_token',
    ];

    protected function casts(): array
    {
        return [
            'email_verified_at' => 'datetime',
            'password' => 'hashed',
        ];
    }

    public function roles(): BelongsToMany
    {
        return $this->belongsToMany(Role::class, 'user_roles');
    }

    public function hasRole(string $role): bool
    {
        return $this->roles()->where('slug', $role)->exists();
    }

    public function hasPermission(string $permission): bool
    {
        return $this->roles()->whereHas('permissions', function ($q) use ($permission) {
            $q->where('slug', $permission);
        })->exists();
    }

    public function assignRole(string $slug): void
    {
        $role = Role::where('slug', $slug)->firstOrFail();
        $this->roles()->syncWithoutDetaching([$role->id]);
    }

    public function vehicles(): HasMany
    {
        return $this->hasMany(Vehicle::class, 'transporteur_id');
    }

    public function identityVerifications(): HasMany
    {
        return $this->hasMany(IdentityVerification::class);
    }

    public function identityDocuments(): HasMany
    {
        return $this->hasMany(IdentityDocument::class);
    }

    public function emergencyContacts(): HasMany
    {
        return $this->hasMany(EmergencyContact::class);
    }

    public function voiceSecurityProfile()
    {
        return $this->hasOne(VoiceSecurityProfile::class);
    }

    public function tripsAsPassager(): HasMany
    {
        return $this->hasMany(Trip::class, 'passager_id');
    }

    public function tripsAsTransporteur(): HasMany
    {
        return $this->hasMany(Trip::class, 'transporteur_id');
    }

    public function sosAlerts(): HasMany
    {
        return $this->hasMany(SosAlert::class, 'passager_id');
    }

    public function notifications(): HasMany
    {
        return $this->hasMany(Notification::class);
    }

    public function auditLogs(): HasMany
    {
        return $this->hasMany(AuditLog::class);
    }

    public function managerAssignments(): HasMany
    {
        return $this->hasMany(ManagerAssignment::class, 'manager_id');
    }

    public function ratingsReceived(): HasMany
    {
        return $this->hasMany(TripRating::class, 'rated_id');
    }

    public function ratingsGiven(): HasMany
    {
        return $this->hasMany(TripRating::class, 'rater_id');
    }

    public function averageRating(): float
    {
        return round((float) ($this->ratingsReceived()->avg('rating') ?? 0), 2);
    }

    public function ratingsCount(): int
    {
        return $this->ratingsReceived()->count();
    }

    /**
     * Statut de vérification d'identité le plus récent (exposé au transporteur).
     */
    public function statutVerification(): ?string
    {
        return $this->identityVerifications()
            ->latest()
            ->value('statut');
    }
}