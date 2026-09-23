<?php

namespace App\Http\Controllers;

use App\Models\QrCode;
use App\Models\SosAlert;
use App\Models\Trip;
use App\Models\TripLocation;
use App\Models\TripRating;
use App\Models\Vehicle;
use App\Models\User;
use App\Models\Notification;
use App\Http\Resources\TripResource;
use App\Services\QrTokenService;
use App\Services\RouteService;
use App\Services\AiService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class TripController extends Controller
{
    /**
     * Nombre maximum de trajets simultanément actifs.
     * - Passager : 1 seul (interdit de lancer un 2e trajet sans terminer
     *   le premier — sinon spam de demandes vers les transporteurs).
     * - Transporteur : jusqu'à 7 (véhicules multi-passagers : minibus…).
     */
    public const MAX_CONCURRENT_TRIPS_PASSAGER = 1;
    public const MAX_CONCURRENT_TRIPS_TRANSPORTEUR = 7;

    /** Statuts comptant comme "trajet réellement actif". */
    public const ACTIVE_TRIP_STATUTS = ['CONFIRME', 'DESTINATION_PROPOSEE', 'DESTINATION_CONFIRMEE', 'EN_COURS', 'FIN_EN_ATTENTE'];
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

        // Tous les statuts actifs : un passager qui a scanné (SCANNE), attend
        // le transporteur (EN_ATTENTE_TRANSPORTEUR) ou défini la destination
        // (CONFIRME / DESTINATION_*) retrouve son trajet en rouvrant l'app.
        $query->whereIn('statut', [
            'SCANNE',
            'EN_ATTENTE_TRANSPORTEUR',
            'CONFIRME',
            'DESTINATION_PROPOSEE',
            'DESTINATION_CONFIRMEE',
            'EN_COURS',
            'FIN_EN_ATTENTE',
        ])->orderByDesc('id');

        $trip = $query->first();

        if (! $trip) {
            return response()->json(['trip' => null]);
        }

        return response()->json(['trip' => TripResource::make($trip)]);
    }

    public function start(Request $request): JsonResponse
    {
        try {
            $data = $request->validate([
                'token' => 'required|string',
                'latitude' => 'required|numeric|between:-90,90',
                'longitude' => 'required|numeric|between:-180,180',
            ]);

            // Compte passager vérifié (KYC) exigé pour lancer une course.
            if (! $request->user()->isIdentiteVerifiee()) {
                return response()->json(['message' => 'Compte non vérifié — vérifiez votre identité pour scanner un QR et lancer une course.'], 403);
            }

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

            // Conducteur vérifié (KYC) exigé : neutralise aussi les véhicules
            // créés avant cette règle.
            if (! $vehicle->transporteur->isIdentiteVerifiee()) {
                return response()->json(['message' => 'Conducteur non vérifié — ce véhicule ne peut pas lancer de course pour le moment.'], 403);
            }

        // UN SEUL trajet RÉELLEMENT actif par passager : impossible d'en
        // lancer un second sans terminer le premier. Un trajet est
        // comptabilisé/définitif une fois la configuration terminée
        // (CONFIRME et suivants).
        // Les étapes de configuration (SCANNE, EN_ATTENTE_TRANSPORTEUR)
        // ne sont pas un vrai trajet : on les annule automatiquement pour
        // que le passager puisse rescanter.
        $activeStatuts = self::ACTIVE_TRIP_STATUTS;

        // Auto-réparation : le scheduler (trips:auto-end-inactive) ne tourne
        // pas forcément en production (ex. Render sans cron) — un trajet
        // actif abandonné (app fermée en EN_COURS, sans update depuis des
        // heures) bloquerait sinon le passager indéfiniment (422 à chaque
        // scan, sans jamais voir les infos transporteur). On clôt en
        // ANNULE/AUTO_PURGE tout trajet "actif" sans mise à jour depuis
        // plus de 6h, AVANT le guard ci-dessous. Un vrai trajet en cours
        // reçoit des mises à jour régulières : 6h sans update = abandonné.
        // EXCLU : FIN_EN_ATTENTE, gouverné par sa propre règle (clôture auto
        // après 24h sans co-confirmation, voir maybeAutoCloseUnconfirmedEnd).
        $staleCutoff = now()->subHours(6);
        $staleCount = Trip::where('passager_id', $request->user()->id)
            ->whereIn('statut', $activeStatuts)
            ->where('statut', '!=', 'FIN_EN_ATTENTE')
            ->where('updated_at', '<', $staleCutoff)
            ->update(['statut' => 'ANNULE', 'end_method' => 'AUTO_PURGE', 'ended_at' => now()]);
        if ($staleCount > 0) {
            \Log::warning('Scan : clôture auto de trajets actifs abandonnés', [
                'passager_id' => $request->user()->id,
                'count' => $staleCount,
            ]);
        }

        $activeCount = Trip::where('passager_id', $request->user()->id)
            ->whereIn('statut', $activeStatuts)
            ->count();

        if ($activeCount >= self::MAX_CONCURRENT_TRIPS_PASSAGER) {
            $existingTrip = Trip::where('passager_id', $request->user()->id)
                ->whereIn('statut', $activeStatuts)
                ->orderByDesc('id')
                ->with('passager', 'transporteur', 'vehicle')
                ->first();

            return response()->json([
                'message' => 'Vous avez déjà un trajet en cours. Terminez-le avant de scanner un nouveau véhicule.',
                'trip' => $existingTrip ? new TripResource($existingTrip) : null,
                'active_trip' => true,
            ], 422);
        }

        // Configuration en cours (scan ou en attente de transporteur) : ce
        // n'est pas un réel trajet, on l'annule pour repartir de zéro.
        Trip::where('passager_id', $request->user()->id)
            ->whereIn('statut', ['SCANNE', 'EN_ATTENTE_TRANSPORTEUR'])
            ->update(['statut' => 'ANNULE']);

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
            \Log::info('Trip start multi-usage QR');

            // P1-24H : le QR n'est PAS consommé par le scan — il reste réutilisable
            // plusieurs fois tant qu'il est actif (validité 24h). L'anti double
            // démarrage est garanti par le guard "trajet réellement actif" ci-dessus.
            $qr->update(['last_used_at' => now()]);

            try {
                $trip = Trip::create([
                    'passager_id' => $request->user()->id,
                    'transporteur_id' => $vehicle->transporteur_id,
                    'vehicle_id' => $vehicle->id,
                    'qr_token' => $qr->token,
                    'start_latitude' => $data['latitude'],
                    'start_longitude' => $data['longitude'],
                    'started_at' => now(),
                    'statut' => 'SCANNE',
                ]);

                Notification::create([
                    'user_id' => $vehicle->transporteur_id,
                    'type' => 'TRAJET',
                    'titre' => 'Un passager a scanné votre QR',
                    'message' => $request->user()->prenom . ' ' . $request->user()->nom . ' a scanné votre véhicule. Il va vous demander d\'accepter la course.',
                    'push' => false,
                ]);

                Notification::create([
                    'user_id' => $request->user()->id,
                    'type' => 'TRAJET',
                    'titre' => 'Transporteur identifié',
                    'message' => 'Véhicule ' . $vehicle->marque . ' ' . $vehicle->modele . ' (' . $vehicle->immatriculation . ') - Transporteur ' . $vehicle->transporteur->prenom . ' ' . $vehicle->transporteur->nom . '. Voulez-vous commencer la course ?',
                    'push' => false,
                ]);
            } catch (\Throwable $e) {
                // Pas de QR à réactiver ici (il n'est jamais désactivé au scan).
                throw $e;
            }
        } catch (\RuntimeException $e) {
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
                    'email' => $vehicle->transporteur->email,
                    'photo_url' => $vehicle->transporteur->photo_url,
                    'average_rating' => $vehicle->transporteur->averageRating(),
                    'ratings_count' => $vehicle->transporteur->ratingsCount(),
                    'verifie' => $vehicle->transporteur->statutVerification(),
                    'trips_count' => Trip::where('transporteur_id', $vehicle->transporteur_id)
                        ->where('statut', 'TERMINE')
                        ->count(),
                    'sos_count' => SosAlert::whereIn('trip_id', $vehicle->transporteur->tripsAsTransporteur()->pluck('id'))
                        ->count(),
                    'reviews' => TripRating::where('rated_id', $vehicle->transporteur_id)
                        ->with('rater:id,prenom,nom')
                        ->latest()
                        ->limit(6)
                        ->get()
                        ->map(fn ($r) => [
                            'id' => $r->id,
                            'rating' => $r->rating,
                            'comment' => $r->comment,
                            'prenom' => $r->rater?->prenom,
                            'nom' => $r->rater?->nom,
                            'created_at' => $r->created_at?->toIso8601String(),
                        ]),
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
     * Le passager accepte de démarrer la course (SCANNE → EN_ATTENTE_TRANSPORTEUR).
     * Le transporteur devra ensuite accepter la course (acceptCourse) ou la refuser.
     */
    public function confirmEmbarquement(Request $request, int $id): JsonResponse
    {
        $trip = Trip::where('id', $id)
            ->where('passager_id', $request->user()->id)
            ->where('statut', 'SCANNE')
            ->firstOrFail();

        $trip->update(['statut' => 'EN_ATTENTE_TRANSPORTEUR']);

        // Le transporteur reçoit une notification push/in-app : la course
        // est proposée, il doit l'accepter ou la refuser depuis son app.
        Notification::create([
            'user_id' => $trip->transporteur_id,
            'type' => 'TRAJET',
                    'titre' => 'Nouvelle course à accepter',
            'message' => 'Le passager ' . $request->user()->prenom . ' ' . $request->user()->nom . ' souhaite commencer une course avec vous. Acceptez-vous la course ?',
            'push' => true,
        ]);

        return response()->json([
            'message' => 'Course proposée au transporteur. En attente de son accord…',
            'trip' => new TripResource($trip->fresh()->load('passager', 'transporteur', 'vehicle')),
            'next_step' => 'waiting_transporteur',
        ]);
    }

    /**
     * Le transporteur accepte la course (EN_ATTENTE_TRANSPORTEUR → CONFIRME).
     */
    public function acceptCourse(Request $request, int $id): JsonResponse
    {
        // Compte transporteur vérifié (KYC) exigé pour accepter une course.
        if (! $request->user()->isIdentiteVerifiee()) {
            return response()->json(['message' => 'Compte non vérifié — vérifiez votre identité pour accepter des courses.'], 403);
        }

        // Un transporteur peut mener jusqu'à MAX_CONCURRENT_TRIPS_TRANSPORTEUR
        // courses simultanées (multi-passagers) : au-delà, il doit en
        // terminer une avant d'accepter.
        $activeStatuts = self::ACTIVE_TRIP_STATUTS;
        $busyCount = Trip::where('transporteur_id', $request->user()->id)
            ->whereIn('statut', $activeStatuts)
            ->where('id', '!=', $id)
            ->count();

        if ($busyCount >= self::MAX_CONCURRENT_TRIPS_TRANSPORTEUR) {
            return response()->json([
                'message' => 'Vous avez déjà ' . self::MAX_CONCURRENT_TRIPS_TRANSPORTEUR . ' courses en cours (maximum). Terminez-en une avant d\'en accepter une autre.',
            ], 422);
        }

        $trip = Trip::where('id', $id)
            ->where('transporteur_id', $request->user()->id)
            ->where('statut', 'EN_ATTENTE_TRANSPORTEUR')
            ->firstOrFail();

        $trip->update(['statut' => 'CONFIRME']);

        Notification::create([
            'user_id' => $trip->passager_id,
            'type' => 'TRAJET',
                    'titre' => 'Transporteur a accepté la course',
            'message' => 'Le transporteur a accepté de commencer la course. Définissez votre destination — écoute automatique activée des deux côtés.',
            'push' => false,
        ]);

        return response()->json([
            'message' => 'Course acceptée. Définissez votre destination — écoute automatique activée des deux côtés.',
            'trip' => new TripResource($trip->fresh()->load('passager', 'transporteur', 'vehicle')),
            'next_step' => 'set_destination',
        ]);
    }

    /**
     * Le passager annule sa demande de course avant le départ réel
     * (SCANNE / EN_ATTENTE_TRANSPORTEUR → ANNULE).
     *
     * Sans ceci, un passager ayant scanné puis abandonné reste piégé par le
     * guard "trajet actif existant" jusqu'à la purge auto (>15 min).
     */
    public function cancelByPassenger(Request $request, int $id): JsonResponse
    {
        $trip = Trip::where('id', $id)
            ->where('passager_id', $request->user()->id)
            ->whereIn('statut', ['SCANNE', 'EN_ATTENTE_TRANSPORTEUR'])
            ->firstOrFail();

        $wasWaiting = $trip->statut === 'EN_ATTENTE_TRANSPORTEUR';

        $trip->update(['statut' => 'ANNULE', 'end_method' => 'ANNULATION_PASSAGER']);

        // Informer le transporteur uniquement si la demande lui avait été transmise.
        if ($wasWaiting) {
            Notification::create([
                'user_id' => $trip->transporteur_id,
                'type' => 'TRAJET',
                'titre' => 'Demande de course annulée',
                'message' => 'Le passager a annulé sa demande de course.',
                'push' => false,
            ]);
        }

        return response()->json([
            'message' => 'Demande de course annulée. Vous pouvez scanner un autre véhicule.',
            'trip' => new TripResource($trip->fresh()->load('passager', 'transporteur', 'vehicle')),
        ]);
    }

    /**
     * Le transporteur refuse la course (EN_ATTENTE_TRANSPORTEUR → ANNULE).
     */
    public function declineCourse(Request $request, int $id): JsonResponse
    {
        $trip = Trip::where('id', $id)
            ->where('transporteur_id', $request->user()->id)
            ->where('statut', 'EN_ATTENTE_TRANSPORTEUR')
            ->firstOrFail();

        $trip->update(['statut' => 'ANNULE', 'end_method' => 'REFUS_TRANSPORTEUR']);

        Notification::create([
            'user_id' => $trip->passager_id,
            'type' => 'TRAJET',
                    'titre' => 'Course refusée par le transporteur',
            'message' => 'Le transporteur a refusé la course. Vous pouvez scanner un autre véhicule.',
            'push' => false,
        ]);

        return response()->json([
            'message' => 'Course refusée. Le passager en a été informé.',
            'trip' => new TripResource($trip->fresh()->load('passager', 'transporteur', 'vehicle')),
        ]);
    }

    /**
     * Trajet proposé au transporteur en cours de décision (EN_ATTENTE_TRANSPORTEUR).
     * GET /trips/pending (transporteur) — renvoie null s'il n'y a rien à accepter.
     */
    public function pending(Request $request): JsonResponse
    {
        $trip = Trip::with('passager', 'transporteur', 'vehicle')
            ->where('transporteur_id', $request->user()->id)
            ->where('statut', 'EN_ATTENTE_TRANSPORTEUR')
            ->orderByDesc('id')
            ->first();

        if (! $trip) {
            return response()->json(['trip' => null]);
        }

        return response()->json(['trip' => new TripResource($trip)]);
    }

    /**
     * État courant d'un trajet (passager ou transporteur).
     * GET /trips/{trip}/status — utilisé pour poller l'acceptation du transporteur.
     */
    public function status(Request $request, int $id): JsonResponse
    {
        $trip = Trip::with('passager', 'transporteur', 'vehicle')
            ->where('id', $id)
            ->where(function ($q) use ($request) {
                $q->where('passager_id', $request->user()->id)
                  ->orWhere('transporteur_id', $request->user()->id);
            })
            ->firstOrFail();

        // Filet 24h : une fin proposée restée sans réponse est clôturée ici
        // (le poll des deux apps passe par status toutes les quelques secondes).
        $this->maybeAutoCloseUnconfirmedEnd($trip);

        return response()->json(['trip' => new TripResource($trip)]);
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

        // PAS de rotation ici : tant que le trajet n'est pas démarré
        // (destination seulement proposée), le QR scanné RESTE valide et
        // réutilisable. La rotation a lieu uniquement au démarrage réel
        // (confirmDestination → EN_COURS, voir rotateTripQr).
        $qrRotation = ['rotated' => false, 'reason' => 'attente_demarrage'];

        return response()->json([
            'message' => 'Destination proposée. Confirmez-vous cette destination ?',
            'trip' => new TripResource($trip->fresh()->load('passager', 'transporteur', 'vehicle')),
            'next_step' => 'confirm_destination',
            'confirmation_required' => true,
            'qr_rotation' => $qrRotation,
        ]);
    }

    /**
     * Confirmation de la destination par le passager
     * Passe le statut de DESTINATION_PROPOSEE → DESTINATION_CONFIRMEE
     * (trace d'audit) puis démarre réellement le trajet (→ EN_COURS).
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

        try {
        // Transition en deux temps pour que le TripObserver audite
        // DESTINATION_PROPOSEE → DESTINATION_CONFIRMEE (destination_confirmee)
        // puis DESTINATION_CONFIRMEE → EN_COURS (trip_start). Sans cette
        // étape intermédiaire, aucun journal d'audit du démarrage n'est écrit.
        $trip->update(['statut' => 'DESTINATION_CONFIRMEE']);
        $trip->update([
            'statut' => 'EN_COURS',
        ]);

        // Rotation auto du QR à l'engagement réel du trajet : le QR scanné
        // est désactivé, un QR frais (actif 24h) attend les prochains
        // passagers. Sauf si une rotation a déjà eu lieu depuis le scan
        // (choix de destination) : le QR actif n'est alors plus celui du
        // trajet (trip.qr_token) — inutile de tourner deux fois.
        // Non bloquant : un échec de rotation ne doit jamais empêcher le
        // démarrage du trajet.
        $qrRotation = $this->rotateTripQr($trip, 'trajet_demarre', true);

        Notification::create([
            'user_id' => $trip->transporteur_id,
            'type' => 'TRAJET',
            'titre' => 'Trajet démarré',
            'message' => 'Le trajet vers ' . $trip->destination_address . ' a commencé.',
        ]);
    } catch (\Throwable $e) {
        // En cas d'erreur de transition d'état, on retourne un message clair
        \Log::error('Erreur lors de la confirmation de destination', [
            'trip_id' => $id,
            'error' => $e->getMessage(),
        ]);
        return response()->json([
            'message' => 'Erreur lors de la mise à jour du statut. Réessayez.',
        ], 500);
    }

        return response()->json([
            'message' => 'Destination confirmée. Trajet en cours.',
            'trip' => new TripResource($trip->fresh()->load('passager', 'transporteur', 'vehicle')),
            'next_step' => 'trajet_en_cours',
            'qr_rotation' => $qrRotation,
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

        // Filet 24h : chaque point GPS réévalue une fin restée sans réponse.
        // Si le trajet vient d'être clôturé, on n'enregistre plus de point.
        if ($this->maybeAutoCloseUnconfirmedEnd($trip)) {
            return response()->json([
                'message' => 'Trajet clôturé automatiquement (fin proposée depuis plus de 24h sans confirmation).',
                'trip' => new TripResource($trip->load('passager', 'transporteur', 'vehicle')),
            ]);
        }

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

        // Détection IA en temps réel : vérifie les anomalies
        // (vitesse, arrêts, perte signal, déviation) et crée
        // une demande de vérification interactive + notification.
        try {
            $this->aiService->checkTripAnomalies($trip);
        } catch (\Throwable $e) {
            // non bloquant
        }

        return response()->json(['message' => 'Position enregistrée'], 201);
    }

    /**
     * Fin de trajet à DOUBLE confirmation (passager + transporteur).
     * - 1er clic (EN_COURS) : le trajet passe en FIN_EN_ATTENTE, on mémorise
     *   qui demande, et l'AUTRE partie est notifiée pour confirmer. Le trajet
     *   n'est PAS terminé.
     * - 2e clic par l'AUTRE partie : TERMINE (finalizeTrip, inchangé).
     * - 2e clic par la MÊME partie : idempotent, toujours en attente.
     * - Sans co-confirmation sous 24h : clôture automatique (AUTO_24H),
     *   évaluée paresseusement (scheduler mort sur Render).
     */
    public function end(Request $request, int $id): JsonResponse
    {
        $trip = $this->ownActiveTrip($request, $id);

        // La clôture manuelle n'a de sens que pour un trajet réellement
        // démarré : avant EN_COURS, on passe par l'annulation (cancel) ou la
        // purge auto. Sinon TERMINE serait posé sans itinéraire, avec une
        // déviation aberrante (distance vers les coordonnées nulles).
        if (! in_array($trip->statut, ['EN_COURS', 'FIN_EN_ATTENTE'])) {
            return response()->json([
                'message' => 'Impossible de terminer un trajet qui n\'a pas démarré. Annulez la demande de course à la place.',
            ], 422);
        }

        // Filet 24h : une demande restée sans réponse est clôturée ici même.
        if ($this->maybeAutoCloseUnconfirmedEnd($trip)) {
            return response()->json([
                'message' => 'Trajet clôturé automatiquement (fin proposée depuis plus de 24h sans confirmation).',
                'trip' => new TripResource($trip->load('passager', 'transporteur', 'vehicle')),
            ]);
        }

        $role = $request->user()->id === $trip->passager_id ? 'passager' : 'transporteur';

        // 1re demande : EN_COURS → FIN_EN_ATTENTE + notification à l'autre.
        if ($trip->statut === 'EN_COURS') {
            $trip->update([
                'statut' => 'FIN_EN_ATTENTE',
                'fin_demandee_par' => $role,
                'fin_demandee_at' => now(),
            ]);

            $asker = $request->user();
            $otherId = $role === 'passager' ? $trip->transporteur_id : $trip->passager_id;
            $otherLabel = $role === 'passager' ? 'votre transporteur' : 'votre passager';
            Notification::create([
                'user_id' => $otherId,
                'type' => 'TRAJET',
                'titre' => 'Fin de course à confirmer',
                'message' => $asker->prenom . ' ' . $asker->nom . ' indique que la course est terminée. Confirmez-vous la fin du trajet ? Sans confirmation sous 24h, il sera clôturé automatiquement.',
                'push' => true,
            ]);

            return response()->json([
                'message' => 'Fin proposée. En attente de confirmation de ' . $otherLabel . ' (clôture auto après 24h sans réponse).',
                'trip' => new TripResource($trip->fresh()->load('passager', 'transporteur', 'vehicle')),
                'end_request' => 'waiting_other',
            ]);
        }

        // FIN_EN_ATTENTE : même demandeur → idempotent ; autre partie → TERMINE.
        if ($trip->fin_demandee_par === $role) {
            return response()->json([
                'message' => 'Fin déjà proposée. En attente de confirmation de l\'autre partie (clôture auto après 24h sans réponse).',
                'trip' => new TripResource($trip->fresh()->load('passager', 'transporteur', 'vehicle')),
                'end_request' => 'waiting_other',
            ]);
        }

        $finished = $this->finalizeTrip($trip, 'MANUEL');

        return response()->json([
            'message' => 'Trajet terminé (fin confirmée des deux côtés)',
            'trip' => new TripResource($finished),
        ]);
    }

    /**
     * Clôture automatique d'une demande de fin restée sans co-confirmation
     * depuis plus de 24h. Évaluation PARESSEUSE (appelée depuis status(),
     * storeLocation() et end()) car le scheduler ne tourne pas forcément en
     * production. Retourne true si elle a clôturé ($trip muté sur place).
     */
    protected function maybeAutoCloseUnconfirmedEnd(Trip $trip): bool
    {
        if ($trip->statut !== 'FIN_EN_ATTENTE') {
            return false;
        }

        $askedAt = $trip->fin_demandee_at;
        if (! $askedAt || $askedAt->gt(now()->subHours(24))) {
            return false;
        }

        $this->finalizeTrip($trip, 'AUTO_24H');

        foreach ([$trip->passager_id, $trip->transporteur_id] as $userId) {
            Notification::create([
                'user_id' => $userId,
                'type' => 'TRAJET',
                'titre' => 'Trajet clôturé automatiquement',
                'message' => 'La fin du trajet, proposée depuis plus de 24h sans confirmation, a été clôturée automatiquement.',
                'push' => false,
            ]);
        }

        \Log::info('Clôture auto 24h d\'une fin non confirmée', ['trip_id' => $trip->id]);

        return true;
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
        // Fin automatique des trajets EN_COURS dont la dernière position GPS
        // remonte à plus de 10 minutes (passager arrivé et parti sans clore).
        $deadline = now()->subMinutes(10);
        $count = 0;

        Trip::where('statut', 'EN_COURS')
            ->whereNotNull('destination_latitude')
            ->get()
            ->each(function (Trip $trip) use ($deadline, &$count) {
                // Point de référence : dernière position enregistrée, à
                // défaut l'heure de démarrage du trajet.
                $lastActivity = $trip->locations()
                    ->orderByDesc('captured_at')
                    ->value('captured_at') ?? $trip->started_at;

                if ($lastActivity->lt($deadline)) {
                    $this->finalizeTrip($trip, 'AUTO_10MIN');
                    $count++;
                }
            });

        // Nettoyage des trajets orphelins : un passager qui a scanné ou attendu
        // le transporteur sans suite depuis > 15 min ne doit plus bloquer la
        // carte "trajet actif" (le guard start exige un statut clôturé).
        $orphanDeadline = now()->subMinutes(15);
        $orphans = Trip::whereIn('statut', ['SCANNE', 'EN_ATTENTE_TRANSPORTEUR', 'CONFIRME', 'DESTINATION_PROPOSEE', 'DESTINATION_CONFIRMEE'])
            ->where('started_at', '<', $orphanDeadline)
            ->get();

        foreach ($orphans as $orphan) {
            $orphan->update(['statut' => 'ANNULE', 'end_method' => 'AUTO_PURGE']);
            Notification::create([
                'user_id' => $orphan->passager_id,
                'type' => 'TRAJET',
                'titre' => 'Trajet annulé automatiquement',
                'message' => 'Votre demande de trajet n\'a pas abouti. Vous pouvez scanner un nouveau véhicule.',
            ]);
            $count++;
        }

        return response()->json(['message' => "$count trajets clôturés automatiquement", 'closed' => $count]);
    }

    public function history(Request $request): JsonResponse
    {
        $role = $request->user()->roles()->first()?->slug;

        // Deux vues : ?scope=en_cours (tout sauf clôturé) ou ?scope=fini
        // (TERMINE, défaut — comportement historique inchangé).
        $scope = $request->query('scope', 'fini');

        $query = Trip::with('passager', 'transporteur', 'vehicle', 'ratings');

        if ($scope === 'en_cours') {
            $query->whereNotIn('statut', ['TERMINE', 'ANNULE']);
        } else {
            $query->where('statut', 'TERMINE');
        }

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

        // En cours : triés par démarrage récent (ended_at est null).
        $trips = $scope === 'en_cours'
            ? $query->latest('started_at')->paginate(15)
            : $query->latest('ended_at')->paginate(15);

        // Enveloppe data/links/meta explicite : une ResourceCollection
        // NICHÉE dans response()->json perd son enveloppe (liste nue) —
        // le mobile lit trips['data']. ->response()->getData(true) la restaure.
        return response()->json([
            'trips' => TripResource::collection($trips)->response()->getData(true),
        ]);
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
            $seg = $this->haversine($coords[$i][0], $coords[$i][1], $coords[$i + 1][0], $coords[$i + 1][1]);
            // Filtre anti-dérive GPS : les micro-segments (< 10 m) sont du
            // bruit de capteur à l'arrêt, pas du roulage — sinon un trajet
            // immobile accumule des "km" fantômes au récapitulatif.
            if ($seg >= 0.010) {
                $distance += $seg;
            }
        }

        return $distance;
    }

    protected function computeDeviation(Trip $trip): float
    {
        // Pas de destination prévue → pas de déviation calculable
        // (sinon la distance serait mesurée vers les coordonnées nulles).
        if ($trip->destination_latitude === null || $trip->destination_longitude === null) {
            return 0;
        }

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

    /**
     * Rotation auto du QR du véhicule d'un trajet (désactive les actifs,
     * crée un actif 24h). JAMAIS bloquante : retourne ['rotated' => bool,
     * 'reason' => string] pour traçabilité (visible dans les réponses
     * setDestination/confirmDestination).
     * - $onlyIfScannedActive = true : ne tourne que si le QR actif est
     *   encore celui scanné (trip.qr_token) — évite les doubles rotations
     *   (ex. déjà tourné au choix de destination).
     * - Repli : si le véhicule du trajet a été remplacé entre-temps, on
     *   tourne celui actuellement détenu par le transporteur.
     * - 1 nouvel essai en cas d'échec transitoire (pooler Neon).
     */
    protected function rotateTripQr(Trip $trip, string $context, bool $onlyIfScannedActive = false): array
    {
        $vehicle = $trip->vehicle;
        if (! $vehicle) {
            $vehicle = Vehicle::where('transporteur_id', $trip->transporteur_id)->first();
        }
        if (! $vehicle) {
            \Log::warning('Rotation QR auto impossible : véhicule introuvable', [
                'trip_id' => $trip->id, 'context' => $context,
            ]);

            return ['rotated' => false, 'reason' => 'vehicule_introuvable'];
        }

        if ($onlyIfScannedActive && $trip->qr_token !== null) {
            $currentActive = $vehicle->qrCodes()
                ->where('actif', true)
                ->orderByDesc('id')
                ->first();
            if (! $currentActive || $currentActive->token !== $trip->qr_token) {
                return ['rotated' => false, 'reason' => 'deja_tourne'];
            }
        }

        $lastError = null;
        for ($attempt = 1; $attempt <= 2; $attempt++) {
            try {
                app(VehicleController::class)->rotateForNewRide($vehicle);

                \Log::info('Rotation QR auto OK', [
                    'trip_id' => $trip->id,
                    'vehicle_id' => $vehicle->id,
                    'context' => $context,
                    'attempt' => $attempt,
                ]);

                return ['rotated' => true, 'reason' => $context];
            } catch (\Throwable $e) {
                $lastError = $e->getMessage();
            }
        }

        \Log::warning('Rotation QR auto échouée (2 essais)', [
            'trip_id' => $trip->id,
            'vehicle_id' => $vehicle->id,
            'context' => $context,
            'error' => $lastError,
        ]);

        return ['rotated' => false, 'reason' => 'echec_rotation'];
    }

    protected function resolveQr(string $token): ?QrCode
    {
        // Vérification cryptographique du QR : le token doit être un payload
        // signé HMAC valide (app.key), non expiré, et son contenu doit
        // correspondre au véhicule en base (anti-clonage/édition du QR).
        $data = app(QrTokenService::class)->verify($token);

        if ($data === null) {
            return null;
        }

        $qr = QrCode::where('token', $token)->first();

        if (! $qr) {
            return null;
        }

        // Cohérence payload ↔ enregistrement (véhicule émetteur).
        if ((int) ($data['vid'] ?? 0) !== $qr->vehicle_id) {
            \Log::warning('QR token valide mais vid incohérent', ['qr_id' => $qr->id, 'payload_vid' => $data['vid'] ?? null]);

            return null;
        }

        return $qr;
    }
}