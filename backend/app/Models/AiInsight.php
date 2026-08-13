<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class AiInsight extends Model
{
    use HasFactory;

    protected $fillable = ['ai_report_id', 'titre', 'description', 'gravite'];

    public function aiReport(): BelongsTo
    {
        return $this->belongsTo(AiReport::class);
    }
}