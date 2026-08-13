<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class AiReport extends Model
{
    use HasFactory;

    protected $fillable = [
        'type',
        'contenu',
        'user_id',
        'trip_id',
        'generateur',
    ];

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function trip(): BelongsTo
    {
        return $this->belongsTo(Trip::class);
    }

    public function insights(): HasMany
    {
        return $this->hasMany(AiInsight::class);
    }
}