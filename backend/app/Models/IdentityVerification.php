<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasOne;

class IdentityVerification extends Model
{
    use HasFactory;

    protected $fillable = [
        'user_id',
        'type',
        'statut',
        'provider_kyc',
        'verifie_le',
        'recto_url',
        'verso_url',
        'selfie_url',
    ];

    protected function casts(): array
    {
        return [
            'verifie_le' => 'datetime',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function document(): HasOne
    {
        return $this->hasOne(IdentityDocument::class, 'verification_id');
    }
}