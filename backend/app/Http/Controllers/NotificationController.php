<?php

namespace App\Http\Controllers;

use App\Models\Notification;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class NotificationController extends Controller
{
    /**
     * Notifications récentes de l'utilisateur connecté (+ compte non lues).
     */
    public function index(Request $request): JsonResponse
    {
        $notifications = Notification::where('user_id', $request->user()->id)
            ->latest()
            ->limit(50)
            ->get();

        return response()->json([
            'notifications' => $notifications,
            'unread_count' => Notification::where('user_id', $request->user()->id)
                ->where('lu', false)
                ->count(),
        ]);
    }

    /**
     * Compte de notifications non lues (pour le badge, polling temps réel).
     */
    public function unreadCount(Request $request): JsonResponse
    {
        return response()->json([
            'unread_count' => Notification::where('user_id', $request->user()->id)
                ->where('lu', false)
                ->count(),
        ]);
    }

    public function markRead(Request $request, int $notification): JsonResponse
    {
        $notif = Notification::where('id', $notification)
            ->where('user_id', $request->user()->id)
            ->firstOrFail();

        $notif->update(['lu' => true, 'read_at' => now()]);

        return response()->json(['message' => 'Notification marquée comme lue']);
    }

    public function markAllRead(Request $request): JsonResponse
    {
        Notification::where('user_id', $request->user()->id)
            ->where('lu', false)
            ->update(['lu' => true, 'read_at' => now()]);

        return response()->json(['message' => 'Toutes les notifications sont lues']);
    }
}
