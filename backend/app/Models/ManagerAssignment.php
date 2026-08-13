<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\MorphTo;

class ManagerAssignment extends Model
{
    use HasFactory;

    protected $fillable = [
        'manager_id',
        'dossier_type',
        'dossier_id',
        'statut',
        'assigned_at',
        'taken_at',
        'closed_at',
    ];

    protected function casts(): array
    {
        return [
            'assigned_at' => 'datetime',
            'taken_at' => 'datetime',
            'closed_at' => 'datetime',
        ];
    }

    public function manager(): BelongsTo
    {
        return $this->belongsTo(User::class, 'manager_id');
    }

    public function dossier(): MorphTo
    {
        return $this->morphTo();
    }
}