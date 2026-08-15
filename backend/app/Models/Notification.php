<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class Notification extends Model
{
    use HasFactory;

    protected $fillable = ['user_id', 'type', 'titre', 'message', 'lu', 'read_at'];

    protected function casts(): array
    {
        return [
            'lu' => 'boolean',
            'read_at' => 'datetime',
        ];
    }

    protected static function booted(): void
    {
        static::created(function (Notification $notification) {
            app(\App\Services\FcmService::class)->sendToUser(
                $notification->user_id,
                $notification->titre,
                $notification->message,
                [
                    'notification_id' => (string) $notification->id,
                    'type' => (string) $notification->type,
                ]
            );
        });
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}