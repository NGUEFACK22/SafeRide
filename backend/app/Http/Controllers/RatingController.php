<?php

namespace App\Http\Controllers;

use App\Models\Trip;
use App\Models\TripRating;
use App\Models\Notification;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class RatingController extends Controller
{
    /**
     * Noter un trajet terminé.
     * POST /trips/{trip}/rate  {rating:1-5, comment?: string}
     * - Passager note le transporteur, transporteur note le passager
     * - Un seul avis par utilisateur et par trajet (PUT pour modifier)
     */
    public function store(Request $request, int $tripId): JsonResponse
    {
        $data = $request->validate([
            'rating' => 'required|integer|min:1|max:5',
            'comment' => 'nullable|string|max:1000',
        ]);

        $trip = Trip::with(['passager','transporteur'])->findOrFail($tripId);
        $user = $request->user();

        // Vérifier que l'utilisateur fait partie du trajet et que le trajet est terminé
        if ($trip->passager_id !== $user->id && $trip->transporteur_id !== $user->id) {
            return response()->json(['message' => 'Vous ne faites pas partie de ce trajet'], 403);
        }
        if ($trip->statut !== 'TERMINE') {
            return response()->json(['message' => 'Seuls les trajets terminés peuvent être notés'], 422);
        }

        // Déterminer la cible de la note
        $ratedId = $trip->passager_id === $user->id ? $trip->transporteur_id : $trip->passager_id;

        // Vérifier qu'une note n'existe pas déjà
        $existing = TripRating::where('trip_id', $trip->id)->where('rater_id', $user->id)->first();
        if ($existing) {
            return response()->json([
                'message' => 'Vous avez déjà noté ce trajet. Utilisez PUT pour modifier.',
                'rating' => $existing->load(['rater','rated','trip']),
            ], 409);
        }

        $rating = TripRating::create([
            'trip_id' => $trip->id,
            'rater_id' => $user->id,
            'rated_id' => $ratedId,
            'rating' => $data['rating'],
            'comment' => $data['comment'] ?? null,
        ]);

        // Notification à la personne notée
        Notification::create([
            'user_id' => $ratedId,
            'type' => 'TRAJET',
            'titre' => 'Nouvelle note reçue : '.$data['rating'].'/5',
            'message' => ($user->prenom.' '.$user->nom).' vous a noté '.$data['rating'].'/5 sur le trajet #'.$trip->id.($data['comment'] ? ' : "'.$data['comment'].'"' : ''),
        ]);

        return response()->json([
            'message' => 'Note enregistrée',
            'rating' => $rating->load(['rater','rated','trip']),
            'stats' => $this->statsForUser($ratedId),
        ], 201);
    }

    public function update(Request $request, int $tripId): JsonResponse
    {
        $data = $request->validate([
            'rating' => 'required|integer|min:1|max:5',
            'comment' => 'nullable|string|max:1000',
        ]);

        $trip = Trip::findOrFail($tripId);
        $user = $request->user();

        $rating = TripRating::where('trip_id', $trip->id)->where('rater_id', $user->id)->firstOrFail();
        $rating->update([
            'rating' => $data['rating'],
            'comment' => $data['comment'] ?? $rating->comment,
        ]);

        return response()->json([
            'message' => 'Note mise à jour',
            'rating' => $rating->load(['rater','rated','trip']),
            'stats' => $this->statsForUser($rating->rated_id),
        ]);
    }

    /**
     * Liste les notes d'un trajet (passager/transporteur du trajet ou gestionnaire/admin)
     */
    public function index(Request $request, int $tripId): JsonResponse
    {
        $trip = Trip::findOrFail($tripId);
        $user = $request->user();
        $role = $user->roles()->first()?->slug;
        $isOwner = $trip->passager_id === $user->id || $trip->transporteur_id === $user->id;
        $isManager = in_array($role, ['gestionnaire','admin'], true);
        if (!$isOwner && !$isManager) {
            return response()->json(['message' => 'Accès refusé'], 403);
        }

        $ratings = TripRating::with(['rater','rated'])
            ->where('trip_id', $trip->id)
            ->latest()
            ->get();

        return response()->json([
            'trip_id' => $trip->id,
            'ratings' => $ratings,
            'average' => round($ratings->avg('rating') ?? 0, 2),
            'count' => $ratings->count(),
        ]);
    }

    /**
     * Notes reçues par l'utilisateur connecté
     */
    public function received(Request $request): JsonResponse
    {
        $ratings = TripRating::with(['rater','trip'])
            ->where('rated_id', $request->user()->id)
            ->latest()
            ->paginate(15);

        $stats = $this->statsForUser($request->user()->id);

        return response()->json([
            'ratings' => $ratings,
            'stats' => $stats,
        ]);
    }

    /**
     * Notes données par l'utilisateur connecté
     */
    public function given(Request $request): JsonResponse
    {
        $ratings = TripRating::with(['rated','trip'])
            ->where('rater_id', $request->user()->id)
            ->latest()
            ->paginate(15);

        return response()->json(['ratings' => $ratings]);
    }

    /**
     * Stats publiques d'un transporteur/passager (moyenne, répartition)
     */
    public function stats(Request $request, int $userId): JsonResponse
    {
        $stats = $this->statsForUser($userId);

        $recent = TripRating::with(['rater','trip'])
            ->where('rated_id', $userId)
            ->latest()
            ->limit(5)
            ->get();

        return response()->json([
            'user_id' => $userId,
            'stats' => $stats,
            'recent_ratings' => $recent,
        ]);
    }

    protected function statsForUser(int $userId): array
    {
        $q = TripRating::where('rated_id', $userId);
        $count = $q->count();
        $avg = $count ? round((float) $q->avg('rating'), 2) : 0;
        $distribution = [];
        for ($i=1; $i<=5; $i++) {
            $distribution[(string)$i] = (clone $q)->where('rating', $i)->count();
        }

        return [
            'count' => $count,
            'average' => $avg,
            'distribution' => $distribution,
        ];
    }
}
