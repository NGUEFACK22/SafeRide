<?php

namespace App\Http\Controllers;

use App\Models\Trip;
use App\Services\RouteService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Suivi GPS public d'un trajet via un lien partageable (share_token).
 * Aucune authentification : quiconque possède le lien voit la position en
 * direct tant que le trajet est actif. Le trajet terminé/annulé, le suivi
 * en direct s'arrête de lui-même (le lien n'est pas réutilisable).
 */
class TripShareController extends Controller
{
    /** Statuts pendant lesquels le suivi live est actif. */
    private const ACTIFS = [
        'SCANNE', 'EN_ATTENTE_TRANSPORTEUR', 'CONFIRME',
        'DESTINATION_PROPOSEE', 'DESTINATION_CONFIRMEE', 'EN_COURS',
    ];

    public function show(string $token): Response
    {
        $trip = Trip::where('share_token', $token)->firstOrFail();

        return response()->view('trip-live', [
            'token' => $token,
            'actif' => in_array($trip->statut, self::ACTIFS),
            'destination' => $trip->destination_address ?? '',
        ])->header('Cache-Control', 'no-store');
    }

    /**
     * Données JSON pour la carte (polling ~7 s).
     * Divulgation minimale : prénoms, plaque, position, itinéraire.
     */
    public function data(Request $request, string $token, RouteService $routeService): JsonResponse
    {
        $trip = Trip::where('share_token', $token)->firstOrFail();

        if (! in_array($trip->statut, self::ACTIFS)) {
            return response()->json([
                'actif' => false,
                'statut' => $trip->statut,
                'ended_at' => optional($trip->ended_at)->toIso8601String(),
            ])->header('Cache-Control', 'no-store');
        }

        $last = $trip->locations()->orderByDesc('captured_at')->first();

        // Tracé réel recent (2 km max d'histoire, ~1 point/15 s) + itinéraire prévu
        $trail = $trip->locations()
            ->orderByDesc('captured_at')
            ->limit(120)
            ->get(['latitude', 'longitude', 'captured_at'])
            ->reverse()
            ->values();

        $planned = $trip->planned_route_polyline
            ? array_map(
                fn (array $p): array => ['lat' => $p[0], 'lng' => $p[1]],
                $routeService->decodePolyline($trip->planned_route_polyline)
            )
            : [];

        return response()->json([
            'actif' => true,
            'statut' => $trip->statut,
            'passager' => trim(($trip->passager->prenom ?? '') . ' ' . ($trip->passager->nom ?? '')),
            'transporteur' => trim(($trip->transporteur->prenom ?? '') . ' ' . ($trip->transporteur->nom ?? '')),
            'vehicule' => $trip->vehicle?->plaque ?? '',
            'destination' => $trip->destination_address,
            'position' => $last ? [
                'lat' => (float) $last->latitude,
                'lng' => (float) $last->longitude,
                'vitesse' => (float) ($last->vitesse_km_h ?? 0),
                'captured_at' => $last->captured_at->toIso8601String(),
            ] : null,
            'trail' => $trail->map(fn ($l): array => [(float) $l->latitude, (float) $l->longitude])->values(),
            'planned' => $planned,
            'serveur_now' => now()->toIso8601String(),
        ])->header('Cache-Control', 'no-store');
    }

    /** URL publique complète du suivi (liens SMS/e-mail/app). */
    public static function shareUrl(Trip $trip): ?string
    {
        if (! $trip->share_token) {
            return null;
        }

        // APP_URL en prod ; à défaut (dev mal configuré), l'hôte de la
        // requête courante — un SOS arrive toujours via HTTP.
        $appUrl = (string) config('app.url');
        if ($appUrl === '' || str_contains($appUrl, 'localhost')) {
            $req = request();
            $appUrl = $req ? $req->getSchemeAndHttpHost() : '';
        }

        return rtrim($appUrl, '/') . '/api/v1/public/suivi/' . $trip->share_token;
    }

    /**
     * Le lien de suivi du trajet, pour le passager ou le transporteur
     * authentifié (bouton « Partager ma position » dans l'app).
     */
    public function link(Request $request, int $trip): JsonResponse
    {
        $model = Trip::where('id', $trip)
            ->where(fn ($q) => $q->where('passager_id', $request->user()->id)
                ->orWhere('transporteur_id', $request->user()->id))
            ->firstOrFail();

        if (! in_array($model->statut, self::ACTIFS)) {
            return response()->json(['message' => 'Le suivi live est réservé aux trajets en cours'], 422);
        }

        return response()->json([
            'url' => self::shareUrl($model),
            'expires_with' => 'trip_end',
        ]);
    }
}
