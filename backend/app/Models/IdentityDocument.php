<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class IdentityDocument extends Model
{
    use HasFactory;

    protected $fillable = [
        'user_id',
        'verification_id',
        'type',
        'numero',
        'fichier_url',
        'ocr_data',
    ];

    protected function casts(): array
    {
        return [
            'ocr_data' => 'array',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function verification(): BelongsTo
    {
        return $this->belongsTo(IdentityVerification::class, 'verification_id');
    }
}