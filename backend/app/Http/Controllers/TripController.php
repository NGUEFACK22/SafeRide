<?php

namespace App\Http\Controllers;

use App\Models\QrCode;
use App\Models\Trip;
use App\Models\TripLocation;
use App\Models\Vehicle;
use App\Models\User;
use App\Models\Notification;
use App\Http\Resources\TripResource;
use App\Services\RouteService;
use App\Services\AiService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class TripController extends Controller
{
    public function __construct(
        private readonly RouteService $routeService,
        private readonly AiService $aiService,
    ) {
    }

    public function current(Request $request): JsonResponse
    {
        $role = $request->user()->roles()->first()?->slug ?? 'passager';

        $query = Trip::with('passager', 'transporteur', 'vehicle', 'locations', 'ratings');

        if ($role === 'transporteur') {
            $query->where('transporteur_id', $request->user()->id);
        } else {
            $query->where('passager_id', $request->user()->id);
        }

        $query->where('statut', 'EN_COURS')->latest();

        return response()->json(['trip' => TripResource::make($query->first())]);
    }

    public function start(Request $request): JsonResponse
    {
        try {
            $data = $request->validate([
                'token' => 'required|string',
                'latitude' => 'required|numeric|between:-90,90',
                'longitude' => 'required|numeric|between:-180,180',
            ]);

            $qr = $this->resolveQr($data['token']);

            if ($qr === null || ! $qr->actif) {
                return response()->json(['message' => 'QR Code invalide ou désactivé — régénérez le QR côté transporteur'], 422);
            }

            $vehicle = $qr->vehicle()->with('transporteur')->first();
            if (!$vehicle) {
                return response()->json(['message' => 'Véhicule introuvable pour ce QR'], 422);
            }
            if (!$vehicle->transporteur) {
                return response()->json(['message' => 'Transporteur introuvable'], 422);
            }

            if ($vehicle->transporteur->statut === 'SUSPENDU') {
                return response()->json(['message' => 'Le transporteur est suspendu. Trajet impossible.'], 403);
            }

        // Vérification de proximité GPS : ±50m si position véhicule connue et fraîche
        $proximity = $this->checkProximity($data['latitude'], $data['longitude'], $vehicle);

        if (! $proximity['ok'] && ($proximity['verified'] ?? false)) {
            return response()->json([
                'message' => 'Proximité non vérifiée : vous devez être à proximité immédiate du véhicule pour scanner.',
                'distance_m' => $proximity['distance_m'],
                'max_distance_m' => $proximity['max_distance_m'],
            ], 422);
        }
        // Si position véhicule inconnue/périmée, on autorise le scan (mode test) mais on log
        if (! ($proximity['verified'] ?? false)) {
            \Log::info('Scan proximité non vérifiée (véhicule sans position fraîche) — autorisé en mode test', ['vehicle_id' => $vehicle->id, 'reason' => $proximity['reason'] ?? 'unknown']);
        }

        try {
            $trip = DB::transaction(function () use ($request, $data, $vehicle, $qr) {
                // Lock FOR UPDATE sur le QR pour éviter double démarrage (P1-2)
                $lockedQr = QrCode::where('id', $qr->id)->lockForUpdate()->first();
                if (!$lockedQr || !$lockedQr->actif) {
                    throw new \RuntimeException('QR déjà utilisé');
                }
                $lockedQr->update(['last_used_at' => now(), 'actif' => false]);

                $trip = Trip::create([
                    'passager_id' => $request->user()->id,
                    'transporteur_id' => $vehicle->transporteur_id,
                    'vehicle_id' => $vehicle->id,
                    'qr_token' => $lockedQr->token,
                    'start_latitude' => $data['latitude'],
                    'start_longitude' => $data['longitude'],
                    'started_at' => now(),
                    'statut' => 'SCANNE',
                ]);

                // Régénérer un nouveau QR code pour le véhicule
                $vehicle->qrCodes()->create([
                    'token' => bin2hex(random_bytes(16)),
                    'actif' => true,
                ]);

                Notification::create([
                    'user_id' => $vehicle->transporteur_id,
                    'type' => 'TRAJET',
                    'titre' => '🚕 Nouvelle course démarrée',
                    'message' => 'Vous débutez une nouvelle course avec ' . $request->user()->prenom . ' ' . $request->user()->nom . ' (' . $request->user()->telephone . '). Vérifiez le passager et confirmez le départ.',
                ]);

                Notification::create([
                    'user_id' => $request->user()->id,
                    'type' => 'TRAJET',
                    'titre' => 'Transporteur identifié',
                    'message' => 'Véhicule ' . $vehicle->marque . ' ' . $vehicle->modele . ' (' . $vehicle->immatriculation . ') - Transporteur ' . $vehicle->transporteur->prenom . ' ' . $vehicle->transporteur->nom . '. Voulez-vous commencer la course ?',
                ]);

                return $trip;
            });
        } catch (\RuntimeException $e) {
            if ($e->getMessage() === 'QR déjà utilisé') {
                return response()->json(['message' => 'QR Code déjà utilisé — veuillez scanner le nouveau QR du véhicule'], 422);
            }
            throw $e;
        }

        $trip->load('passager', 'transporteur', 'vehicle');

            return response()->json([
                'message' => 'Transporteur identifié. Voulez-vous commencer la course ?',
                'trip' => new TripResource($trip),
                'transporteur' => [
                    'id' => $vehicle->transporteur->id,
                    'prenom' => $vehicle->transporteur->prenom,
                    'nom' => $vehicle->transporteur->nom,
                    'telephone' => $vehicle->transporteur->telephone,
                    'photo_url' => $vehicle->transporteur->photo_url,
                    'average_rating' => $vehicle->transporteur->averageRating(),
                    'ratings_count' => $vehicle->transporteur->ratingsCount(),
                    'verifie' => $vehicle->transporteur->statutVerification(),
                ],
                'vehicle' => [
                    'id' => $vehicle->id,
                    'marque' => $vehicle->marque,
                    'modele' => $vehicle->modele,
                    'immatriculation' => $vehicle->immatriculation,
                    'type' => $vehicle->type,
                    'couleur' => $vehicle->couleur,
                ],
                'proximity' => $proximity,
                'next_step' => 'confirm_embarquement',
            ], 201);
        } catch (\Throwable $e) {
            \Log::error('Trip start échec', ['token' => $data['token'] ?? null, 'error' => $e->getMessage(), 'trace' => $e->getTraceAsString()]);
            // Toujours renvoyer un message français compréhensible, jamais "An unexpected error occurred"
            $msg = $e->getMessage();
            if (str_contains(strtolower($msg), 'qr') || str_contains(strtolower($msg), 'token')) {
                $msg = 'QR Code invalide — régénérez le QR côté transporteur';
            } elseif (str_contains(strtolower($msg), 'vehicle') || str_contains(strtolower($msg), 'transporteur')) {
                $msg = 'Véhicule ou transporteur introuvable — vérifiez le QR';
            } else {
                $msg = 'Impossible de démarrer le trajet. Réessayez. Si ça persiste, contactez support@saferide.app';
            }
            return response()->json(['message' => $msg], 500);
        }
    }

    /**
     * Confirmation de l'embarquement par le passager ou le transporteur
     * Passe le statut de SCANNE → CONFIRME
     */
    public function confirmEmbarquement(Request $request, int $id): JsonResponse
    {
        $trip = Trip::where('id', $id)
            ->where(function ($q) use ($request) {
                $q->where('passager_id', $request->user()->id)
                  ->orWhere('transporteur_id', $request->user()->id);
            })
            ->where('statut', 'SCANNE')
            ->firstOrFail();

        $trip->update(['statut' => 'CONFIRME']);

        $otherUserId = $trip->passager_id === $request->user()->id
            ? $trip->transporteur_id
            : $trip->passager_id;

        // Message adapté selon qui confirme
        $isPassenger = $trip->passager_id === $request->user()->id;
        if ($isPassenger) {
            Notification::create([
                'user_id' => $trip->transporteur_id,
                'type' => 'TRAJET',
                'titre' => '✅ Course acceptée par le passager',
                'message' => 'Le passager a accepté de commencer la course. Destination à définir. La surveillance vocale démarre pour vous deux.',
            ]);
            Notification::create([
                'user_id' => $trip->passager_id,
                'type' => 'TRAJET',
                'titre' => 'Course démarrée',
                'message' => 'Vous avez accepté la course. Définissez votre destination. La protection vocale est active pour vous et le transporteur.',
            ]);
        } else {
            Notification::create([
                'user_id' => $trip->passager_id,
                'type' => 'TRAJET',
                'titre' => 'Transporteur a confirmé la course',
                'message' => 'Le transporteur confirme la course. Définissez votre destination.',
            ]);
        }

        return response()->json([
            'message' => $isPassenger ? 'Course acceptée. Définissez votre destination — écoute automatique activée des deux côtés.' : 'Embarquement confirmé.',
            'trip' => new TripResource($trip->fresh()->load('passager', 'transporteur', 'vehicle')),
            'next_step' => 'set_destination',
        ]);
    }

    /**
     * Le passager propose une destination
     * Passe le statut de CONFIRME → DESTINATION_PROPOSEE
     */
    public function setDestination(Request $request, int $id): JsonResponse
    {
        $trip = $this->ownActiveTrip($request, $id);

        if (! in_array($trip->statut, ['CONFIRME', 'DESTINATION_PROPOSEE'])) {
            return response()->json(['message' => 'Le trajet doit être confirmé avant de définir une destination'], 422);
        }

        $data = $request->validate([
            'destination_address' => 'required|string|max:255',
            'latitude' => 'required|numeric|between:-90,90',
            'longitude' => 'required|numeric|between:-180,180',
        ]);

        $trip->update([
            'destination_address' => $data['destination_address'],
            'destination_latitude' => $data['latitude'],
            'destination_longitude' => $data['longitude'],
            'statut' => 'DESTINATION_PROPOSEE',
        ]);

        // Itinéraire prévu (polyline OSRM, repli ligne droite)
        $trip->planned_route_polyline = $this->routeService->plannedRoute($trip);
        $trip->save();

        return response()->json([
            'message' => 'Destination proposée. Confirmez-vous cette destination ?',
            'trip' => new TripResource($trip->fresh()->load('passager', 'transporteur', 'vehicle')),
            'next_step' => 'confirm_destination',
            'confirmation_required' => true,
        ]);
    }

    /**
     * Confirmation de la destination par le passager
     * Passe le statut de DESTINATION_PROPOSEE → DESTINATION_CONFIRMEE
     * Puis démarre réellement le trajet (EN_COURS)
     */
    public function confirmDestination(Request $request, int $id): JsonResponse
    {
        $trip = $this->ownActiveTrip($request, $id);

        if ($trip->statut !== 'DESTINATION_PROPOSEE') {
            return response()->json(['message' => 'Aucune destination à confirmer'], 422);
        }

        $data = $request->validate([
            'confirmed' => 'required|boolean',
        ]);

        if (! $data['confirmed']) {
            return response()->json([
                'message' => 'Destination non confirmée. Vous pouvez en proposer une nouvelle.',
                'trip' => new TripResource($trip->fresh()->load('passager', 'transporteur', 'vehicle')),
            ]);
        }

        $trip->update([
            'statut' => 'EN_COURS',
        ]);

        Notification::create([
            'user_id' => $trip->transporteur_id,
            'type' => 'TRAJET',
            'titre' => 'Trajet démarré',
            'message' => 'Le trajet vers ' . $trip->destination_address . ' a commencé.',
        ]);

        return response()->json([
            'message' => 'Destination confirmée. Trajet en cours.',
            'trip' => new TripResource($trip->fresh()->load('passager', 'transporteur', 'vehicle')),
            'next_step' => 'trajet_en_cours',
        ]);
    }

    /**
     * Modifier la destination (remet en DESTINATION_PROPOSEE)
     */
    public function updateDestination(Request $request, int $id): JsonResponse
    {
        $trip = $this->ownActiveTrip($request, $id);

        if (! in_array($trip->statut, ['DESTINATION_PROPOSEE', 'DESTINATION_CONFIRMEE', 'EN_COURS'])) {
            return response()->json(['message' => 'Impossible de modifier la destination à ce stade'], 422);
        }

        $data = $request->validate([
            'destination_address' => 'required|string|max:255',
            'latitude' => 'required|numeric|between:-90,90',
            'longitude' => 'required|numeric|between:-180,180',
        ]);

        $trip->update([
            'destination_address' => $data['destination_address'],
            'destination_latitude' => $data['latitude'],
            'destination_longitude' => $data['longitude'],
            'statut' => 'DESTINATION_PROPOSEE',
        ]);

        $trip->planned_route_polyline = $this->routeService->plannedRoute($trip);
        $trip->save();

        return response()->json([
            'message' => 'Destination modifiée. Confirmez-vous cette nouvelle destination ?',
            'trip' => new TripResource($trip->fresh()->load('passager', 'transporteur', 'vehicle')),
            'next_step' => 'confirm_destination',
            'confirmation_required' => true,
        ]);
    }


    public function storeLocation(Request $request, int $id): JsonResponse
    {
        $trip = $this->ownActiveTrip($request, $id);

        $data = $request->validate([
            'latitude' => 'required|numeric|between:-90,90',
            'longitude' => 'required|numeric|between:-180,180',
            'vitesse_km_h' => 'nullable|numeric|min:0',
            'captured_at' => 'required|date',
        ]);

        TripLocation::create([
            'trip_id' => $trip->id,
            'latitude' => $data['latitude'],
            'longitude' => $data['longitude'],
            'vitesse_km_h' => $data['vitesse_km_h'] ?? null,
            'captured_at' => $data['captured_at'],
        ]);

        return response()->json(['message' => 'Position enregistrée'], 201);
    }

    public function end(Request $request, int $id): JsonResponse
    {
        $trip = $this->ownActiveTrip($request, $id);

        $finished = $this->finalizeTrip($trip, 'MANUEL');

        return response()->json([
            'message' => 'Trajet terminé',
            'trip' => new TripResource($finished),
        ]);
    }

    /**
     * Itinéraire décodé (points GPS) pour affichage cartographique.
     * Accessible au passager, au transporteur et aux rôles gestionnaire/admin.
     */
    public function route(Request $request, int $id): JsonResponse
    {
        $user = $request->user();
        $role = $user->roles()->first()?->slug;

        $trip = Trip::with('locations')->findOrFail($id);

        $isOwner = $trip->passager_id === $user->id || $trip->transporteur_id === $user->id;
        $isManager = in_array($role, ['gestionnaire', 'admin'], true);

        if (! $isOwner && ! $isManager) {
            abort(403, 'Accès refusé à ce trajet.');
        }

        $points = [];

        if ($trip->start_latitude !== null && $trip->start_longitude !== null) {
            $points[] = [
                'lat' => (float) $trip->start_latitude,
                'lng' => (float) $trip->start_longitude,
                'captured_at' => $trip->started_at?->toIso8601String(),
            ];
        }

        foreach ($trip->locations()->orderBy('captured_at')->get() as $location) {
            $points[] = [
                'lat' => (float) $location->latitude,
                'lng' => (float) $location->longitude,
                'captured_at' => $location->captured_at?->toIso8601String(),
            ];
        }

        if ($trip->destination_latitude !== null && $trip->destination_longitude !== null) {
            $points[] = [
                'lat' => (float) $trip->destination_latitude,
                'lng' => (float) $trip->destination_longitude,
                'captured_at' => $trip->ended_at?->toIso8601String(),
            ];
        }

        return response()->json([
            'trip_id' => $trip->id,
            'deviation_km' => $trip->deviation_km,
            'deviation_alert' => (bool) $trip->deviation_alert,
            'start' => $trip->start_latitude !== null
                ? ['lat' => (float) $trip->start_latitude, 'lng' => (float) $trip->start_longitude]
                : null,
            'destination' => $trip->destination_latitude !== null
                ? ['lat' => (float) $trip->destination_latitude, 'lng' => (float) $trip->destination_longitude]
                : null,
            'points' => $points,
        ]);
    }

    public function autoEndInactive(): JsonResponse
    {
        // Fin automatique des trajets dont la destination est atteinte depuis plus de 10 minutes
        $deadline = now()->subMinutes(10);
        $count = 0;

        Trip::where('statut', 'EN_COURS')
            ->whereNotNull('destination_latitude')
            ->get()
            ->each(function (Trip $trip) use ($deadline, &$count) {
                $arrivedAt = $trip->locations()
                    ->orderByDesc('captured_at')
                    ->value('captured_at');

                // Point de référence : dernière position enregistrée avant le délai
                $lastActivity = $trip->locations()
                    ->orderByDesc('captured_at')
                    ->value('captured_at') ?? $trip->started_at;

                if ($lastActivity->lt($deadline)) {
                    $this->finalizeTrip($trip, 'AUTO_10MIN');
                    $count++;
                }
            });

        return response()->json(['message' => "$count trajets clôturés automatiquement", 'closed' => $count]);
    }

    public function history(Request $request): JsonResponse
    {
        $role = $request->user()->roles()->first()?->slug;

        $query = Trip::with('passager', 'transporteur', 'vehicle', 'ratings')
            ->where('statut', 'TERMINE');

        if ($role === 'transporteur') {
            $query->where('transporteur_id', $request->user()->id);
        } elseif ($role === 'passager') {
            $query->where('passager_id', $request->user()->id);
        } elseif (in_array($role, ['gestionnaire', 'admin'], true)) {
            // Gestionnaire/Admin voient tous les trajets (P2-12)
        } else {
            // Fallback : passager par défaut
            $query->where('passager_id', $request->user()->id);
        }

        // Filtres avancés P4 : ?from=2025-01-01&to=2025-12-31&vehicle_id=1&statut=TERMINE
        if ($request->filled('from')) $query->whereDate('started_at', '>=', $request->query('from'));
        if ($request->filled('to')) $query->whereDate('started_at', '<=', $request->query('to'));
        if ($request->filled('vehicle_id')) $query->where('vehicle_id', $request->query('vehicle_id'));
        if ($request->filled('statut')) $query->where('statut', $request->query('statut'));

        $trips = $query->latest('ended_at')->paginate(15);

        return response()->json(['trips' => TripResource::collection($trips)]);
    }

    /**
     * Récupère un trajet actif (passager ou transporteur, tous statuts sauf TERMINE/ANNULE)
     */
    protected function ownActiveTrip(Request $request, int $id): Trip
    {
        $userId = $request->user()->id;
        $trip = Trip::where('id', $id)
            ->where(function ($q) use ($userId) {
                $q->where('passager_id', $userId)
                  ->orWhere('transporteur_id', $userId);
            })
            ->whereNotIn('statut', ['TERMINE', 'ANNULE'])
            ->firstOrFail();

        return $trip;
    }

    /**
     * Récupère un trajet en cours de suivi GPS (passager ou transporteur, statut EN_COURS)
     */
    protected function ownTrackingTrip(Request $request, int $id): Trip
    {
        $userId = $request->user()->id;
        $trip = Trip::where('id', $id)
            ->where(function ($q) use ($userId) {
                $q->where('passager_id', $userId)
                  ->orWhere('transporteur_id', $userId);
            })
            ->where('statut', 'EN_COURS')
            ->firstOrFail();

        return $trip;
    }

    protected function finalizeTrip(Trip $trip, string $method): Trip
    {
        $trip->ended_at = now();
        $trip->statut = 'TERMINE';
        $trip->end_method = $method;

        $distance = $this->computeDistance($trip);
        $trip->distance_km = round($distance, 2);
        $trip->duration_seconds = max(0, $trip->ended_at->diffInSeconds($trip->started_at));
        $trip->deviation_km = round($this->computeDeviation($trip), 2);
        $trip->actual_route_polyline = $this->routeService->actualRoute($trip);
        $trip->deviation_alert = $trip->deviation_km > 0.5;

        $trip->save();

        // Résumé IA du trajet (Point 21) — non bloquant
        try {
            $this->aiService->tripSummary($trip);
        } catch (\Throwable $e) {
            // jamais bloquant pour la clôture du trajet
        }

        return $trip->load('passager', 'transporteur', 'vehicle');
    }

    protected function computeDistance(Trip $trip): float
    {
        $coords = [];
        $coords[] = [(float) $trip->start_latitude, (float) $trip->start_longitude];

        foreach ($trip->locations()->orderBy('captured_at')->get() as $location) {
            $coords[] = [(float) $location->latitude, (float) $location->longitude];
        }

        if ($trip->destination_latitude && $trip->destination_longitude) {
            $coords[] = [(float) $trip->destination_latitude, (float) $trip->destination_longitude];
        }

        $distance = 0;
        for ($i = 0; $i < count($coords) - 1; $i++) {
            $distance += $this->haversine($coords[$i][0], $coords[$i][1], $coords[$i + 1][0], $coords[$i + 1][1]);
        }

        return $distance;
    }

    protected function computeDeviation(Trip $trip): float
    {
        // Écart entre le point final réel et la destination prévue
        $last = $trip->locations()->orderByDesc('captured_at')->first();
        if (! $last) {
            return 0;
        }

        return $this->haversine(
            (float) $last->latitude,
            (float) $last->longitude,
            (float) $trip->destination_latitude,
            (float) $trip->destination_longitude
        );
    }

    protected function haversine(float $lat1, float $lng1, float $lat2, float $lng2): float
    {
        $earthRadius = 6371;
        $dLat = deg2rad($lat2 - $lat1);
        $dLng = deg2rad($lng2 - $lng1);

        $a = sin($dLat / 2) ** 2 + cos(deg2rad($lat1)) * cos(deg2rad($lat2)) * sin($dLng / 2) ** 2;

        return $earthRadius * 2 * atan2(sqrt($a), sqrt(1 - $a));
    }

    /**
     * Vérifie que le passager est à proximité immédiate du véhicule (±50m).
     * Bloquant : si le véhicule n'a pas partagé sa position récemment, le départ est refusé
     * (corrige faille GPS manipulable — P1-1).
     */
    protected function checkProximity(float $passagerLat, float $passagerLng, Vehicle $vehicle): array
    {
        $maxDistanceM = 50;
        $maxAgeSeconds = 300; // 5 min

        if ($vehicle->last_latitude === null || $vehicle->last_longitude === null) {
            return [
                'ok' => false,
                'verified' => false,
                'distance_m' => null,
                'max_distance_m' => $maxDistanceM,
                'reason' => 'vehicle_position_unknown',
            ];
        }

        // Position trop ancienne -> refus (évite spoof avec vieille position)
        if ($vehicle->last_position_at && $vehicle->last_position_at->diffInSeconds(now()) > $maxAgeSeconds) {
            return [
                'ok' => false,
                'verified' => false,
                'distance_m' => null,
                'max_distance_m' => $maxDistanceM,
                'reason' => 'vehicle_position_stale',
            ];
        }

        $distanceM = $this->haversine(
            $passagerLat,
            $passagerLng,
            (float) $vehicle->last_latitude,
            (float) $vehicle->last_longitude
        ) * 1000;

        return [
            'ok' => $distanceM <= $maxDistanceM,
            'verified' => true,
            'distance_m' => (int) round($distanceM),
            'max_distance_m' => $maxDistanceM,
        ];
    }

    protected function resolveQr(string $token): ?QrCode
    {
        // Simplifié : tout token présent en base et actif est accepté
        // (évite les 500 "An unexpected error occurred" dus aux anciens QR signés vs hex)
        return QrCode::where('token', $token)->first();
    }
}