<?php

namespace App\Services;

use App\Models\AiInsight;
use App\Models\AiReport;
use App\Models\AnomalyVerification;
use App\Models\Dispute;
use App\Models\ManagerAssignment;
use App\Models\Notification;
use App\Models\SosAlert;
use App\Models\Trip;
use App\Models\TripLocation;
use App\Models\User;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Http;

/**
 * Service IA (Point 21 / 23) : génère des résumés et statistiques adaptés au
 * rôle de l'utilisateur via une API compatible OpenAI (Chat Completions).
 * Repli déterministe si l'API n'est pas configurée / indisponible.
 */
class AiService
{
    public function isEnabled(): bool
    {
        return (bool) config('services.ai.enabled') && ! empty(config('services.ai.api_key'));
    }

    /**
     * Appel générique à l'API de chat. Renvoie le texte ou null en cas d'échec.
     */
    public function complete(string $system, string $prompt): ?string
    {
        if (! $this->isEnabled()) {
            return null;
        }

        try {
            $response = Http::withToken(config('services.ai.api_key'))
                ->timeout((int) config('services.ai.timeout'))
                ->post(rtrim(config('services.ai.base_url'), '/') . '/chat/completions', [
                    'model' => config('services.ai.model'),
                    'temperature' => 0.3,
                    'messages' => [
                        ['role' => 'system', 'content' => $system],
                        ['role' => 'user', 'content' => $prompt],
                    ],
                ]);

            if (! $response->successful()) {
                return null;
            }

            return $response->json('choices.0.message.content');
        } catch (\Throwable $e) {
            return null;
        }
    }

    /**
     * Résumé d'un trajet (passager + transporteur). Généré à la clôture du trajet.
     */
    public function tripSummary(Trip $trip): AiReport
    {
        $data = $this->tripData($trip);

        $system = "Tu es l'assistant IA de SafeRide, une plateforme de sécurité des trajets "
            . "partagés. Rédige un résumé clair et rassurant en français (3-5 phrases) pour le "
            . "passager et le transporteur, en mentionnant distance, durée, écart d'itinéraire et "
            . "incidents éventuels.";

        $prompt = "Données du trajet #{$trip->id} :\n" . json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE);

        $contenu = $this->complete($system, $prompt)
            ?? $this->fallbackTripSummary($data);

        $report = AiReport::create([
            'type' => 'RESUME_TRAJET',
            'contenu' => $contenu,
            'user_id' => $trip->passager_id,
            'trip_id' => $trip->id,
            'generateur' => $this->isEnabled() ? 'IA_SafeRide' : 'REGLE',
        ]);

        if ($trip->deviation_alert) {
            AiInsight::create([
                'ai_report_id' => $report->id,
                'titre' => 'Écart d\'itinéraire important',
                'description' => "Le trajet #{$trip->id} présente un écart de "
                    . ($trip->deviation_km ?? 0) . " km par rapport à l'itinéraire prévu.",
                'gravite' => 'MOYENNE',
            ]);
        }

        return $report;
    }

    /**
     * Statistiques adaptées au rôle de l'utilisateur.
     */
    public function userStats(User $user): AiReport
    {
        $role = $user->roles()->first()?->slug ?? 'passager';
        $data = $this->roleData($user, $role);

        $libelles = [
            'passager' => 'passager',
            'transporteur' => 'transporteur',
            'gestionnaire' => 'gestionnaire de dossiers de sécurité',
            'admin' => 'administrateur de la plateforme',
        ];

        $system = "Tu es l'assistant IA de SafeRide. Tu fournis à un {$libelles[$role]} un "
            . "bilan personnalisé de son activité, en français, sous forme de points clairs "
            . "(puces). Mets en avant ce qui compte pour son rôle et donne 1 à 2 recommandations.";

        $prompt = "Statistiques pour l'utilisateur #{$user->id} (rôle : {$role}) :\n"
            . json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE);

        $contenu = $this->complete($system, $prompt)
            ?? $this->fallbackUserStats($user, $role, $data);

        return AiReport::create([
            'type' => 'STATISTIQUES',
            'contenu' => $contenu,
            'user_id' => $user->id,
            'generateur' => $this->isEnabled() ? 'IA_SafeRide' : 'REGLE',
        ]);
    }

    /**
     * Résumé hebdomadaire de l'activité de l'utilisateur (généré le dimanche
     * par la commande planifiée, ou à la demande via GET /ai/weekly).
     */
    public function weeklyReport(User $user): AiReport
    {
        $role = $user->roles()->first()?->slug ?? 'passager';
        $data = $this->weeklyData($user, $role);

        $libelles = [
            'passager' => 'passager',
            'transporteur' => 'transporteur',
            'gestionnaire' => 'gestionnaire de dossiers de sécurité',
            'admin' => 'administrateur de la plateforme',
        ];

        $system = "Tu es l'assistant IA de SafeRide. Rédige en français un résumé "
            . "hebdomadaire (semaine écoulée) pour un {$libelles[$role]}, en 4-6 phrases "
            . "claires et rassurantes, avec 1-2 recommandations pour la semaine à venir. "
            . "Mentionne les faits marquants (trajets, SOS, incidents, anomalies).";

        $prompt = "Semaine du {$data['debut_semaine']} au {$data['fin_semaine']} "
            . "(rôle : {$role}) :\n"
            . json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE);

        $contenu = $this->complete($system, $prompt)
            ?? $this->fallbackWeeklyReport($user, $role, $data);

        return AiReport::create([
            'type' => 'RAPPORT_HEBDOMADAIRE',
            'contenu' => $contenu,
            'user_id' => $user->id,
            'generateur' => $this->isEnabled() ? 'IA_SafeRide' : 'REGLE',
        ]);
    }

    /**
     * Données agrégées de la semaine écoulée (lundi -> aujourd'hui).
     */
    protected function weeklyData(User $user, string $role): array
    {
        $debut = now()->startOfWeek();
        $fin = now()->endOfWeek();

        $trajetsQuery = Trip::whereBetween('created_at', [$debut, $fin]);

        $data = [
            'debut_semaine' => $debut->format('d/m/Y'),
            'fin_semaine' => $fin->format('d/m/Y'),
        ];

        $data += match ($role) {
            'transporteur' => [
                'trajets_effectues' => $user->tripsAsTransporteur()->whereBetween('created_at', [$debut, $fin])->count(),
                'distance_totale_km' => round((float) ($user->tripsAsTransporteur()->whereBetween('created_at', [$debut, $fin])->sum('distance_km') ?? 0), 2),
                'ecarts_itineraire' => $user->tripsAsTransporteur()->whereBetween('created_at', [$debut, $fin])->where('deviation_alert', true)->count(),
                'sos' => SosAlert::whereIn('trip_id', $user->tripsAsTransporteur()->whereBetween('created_at', [$debut, $fin])->pluck('id'))->count(),
            ],
            'gestionnaire' => [
                'dossiers_attribues' => $user->managerAssignments()->whereBetween('created_at', [$debut, $fin])->count(),
                'dossiers_clotures' => $user->managerAssignments()->whereBetween('created_at', [$debut, $fin])->where('statut', 'CLOTURE')->count(),
                'sos_en_cours' => SosAlert::where('statut', '!=', 'RESOLU')->whereBetween('created_at', [$debut, $fin])->count(),
            ],
            'admin' => [
                'total_trajets' => (clone $trajetsQuery)->count(),
                'total_sos' => SosAlert::whereBetween('created_at', [$debut, $fin])->count(),
                'nouveaux_utilisateurs' => User::whereBetween('created_at', [$debut, $fin])->count(),
                'anomalies' => AiReport::where('type', 'ANOMALIE')->whereBetween('created_at', [$debut, $fin])->count(),
            ],
            default => [
                'trajets_effectues' => $user->tripsAsPassager()->whereBetween('created_at', [$debut, $fin])->count(),
                'distance_totale_km' => round((float) ($user->tripsAsPassager()->whereBetween('created_at', [$debut, $fin])->sum('distance_km') ?? 0), 2),
                'sos' => SosAlert::where('passager_id', $user->id)->whereBetween('created_at', [$debut, $fin])->count(),
                'litiges' => Dispute::where('passager_id', $user->id)->whereBetween('created_at', [$debut, $fin])->count(),
            ],
        };

        return $data;
    }

    protected function fallbackWeeklyReport(User $user, string $role, array $d): string
    {
        $lines = ["Bilan de la semaine du {$d['debut_semaine']} au {$d['fin_semaine']} "
            . "({$role}, utilisateur #{$user->id}) :"];
        foreach ($d as $k => $v) {
            if (str_starts_with($k, 'debut_') || str_starts_with($k, 'fin_')) {
                continue;
            }
            $lines[] = "- $k : $v";
        }

        return implode("\n", $lines);
    }

    /**
     * Détection d'anomalies globales (pour gestionnaire / admin).
     * Analyse en temps réel le comportement du trajet et recherche des
     * situations anormales à partir de plusieurs indicateurs :
     *  - 📍 Écarts d'itinéraire répétés par un même transporteur
     *  - 🎙️ SOS vocaux non vérifiés
     *  - 🚗 Vitesse excessive / arrêts inhabituels (GPS locations)
     *  - 📵 Perte prolongée de mouvement (trajets actifs sans update)
     *  - 🔄 Déviations d'itinéraire améliorées (comparaison polyline)
     */
    public function detectAnomalies(): array
    {
        $anomalies = [];
        $anomalies = array_merge($anomalies, $this->detectRepeatDeviation());
        $anomalies = array_merge($anomalies, $this->detectUnverifiedSos());
        $anomalies = array_merge($anomalies, $this->detectSpeedAnomalies());
        $anomalies = array_merge($anomalies, $this->detectUnusualStops());
        $anomalies = array_merge($anomalies, $this->detectMovementLoss());
        $anomalies = array_merge($anomalies, $this->detectRouteDetours());

        return $anomalies;
    }

    // -------------------------------------------------------------------------
    // Sous-détecteurs d'anomalies
    // -------------------------------------------------------------------------

    /**
     * Transporteurs avec écarts d'itinéraire répétés (≥2 trajets avec deviation_alert).
     */
    protected function detectRepeatDeviation(): array
    {
        $anomalies = [];

        $repeatDeviation = Trip::where('deviation_alert', true)
            ->where('statut', 'TERMINE')
            ->selectRaw('transporteur_id, COUNT(*) as c')
            ->groupBy('transporteur_id')
            ->having('c', '>=', 2)
            ->get();

        foreach ($repeatDeviation as $row) {
            $anomalies[] = [
                'titre' => 'Écarts d\'itinéraire répétés',
                'description' => "Le transporteur #{$row->transporteur_id} présente "
                    . "{$row->c} trajets avec écart important par rapport à l'itinéraire prévu.",
                'gravite' => 'ELEVEE',
            ];
        }

        return $anomalies;
    }

    /**
     * SOS vocaux en attente de vérification (verbal + empreinte non validés).
     */
    protected function detectUnverifiedSos(): array
    {
        $anomalies = [];

        $unverified = SosAlert::where('declenchement', 'VOCAL')
            ->where('statut', 'VERIFICATION')
            ->count();

        if ($unverified > 0) {
            $anomalies[] = [
                'titre' => 'Alertes SOS vocales non vérifiées',
                'description' => "$unverified alerte(s) SOS vocale(s) en attente de vérification du mot-clé et de l'empreinte vocale.",
                'gravite' => 'MOYENNE',
            ];
        }

        return $anomalies;
    }

    /**
     * 🚗 Vitesse excessive : repère les locations où la vitesse > 120 km/h
     * (seuil adapté aux routes urbaines / nationales camerounaises).
     */
    protected function detectSpeedAnomalies(): array
    {
        $anomalies = [];

        $speedThreshold = 120; // km/h — vitesse anormale pour routes du Cameroun

        $speedHits = TripLocation::where('vitesse_km_h', '>', $speedThreshold)
            ->selectRaw('trip_id, MAX(vitesse_km_h) as max_speed, COUNT(*) as count')
            ->groupBy('trip_id')
            ->get();

        foreach ($speedHits as $row) {
            $trip = Trip::with('transporteur')->find($row->trip_id);
            if (! $trip) {
                continue;
            }
            $driver = $trip->transporteur;
            $driverName = $driver ? $driver->prenom . ' ' . $driver->nom : "transporteur #{$trip->transporteur_id}";

            $anomalies[] = [
                'titre' => 'Vitesse excessive détectée',
                'description' => "Le trajet #{$row->trip_id} ({$driverName}) a enregistré "
                    . "{$row->count} point(s) avec une vitesse maximale de "
                    . round($row->max_speed, 1) . " km/h — seuil dépassé: {$speedThreshold} km/h.",
                'gravite' => 'ELEVEE',
            ];
        }

        return $anomalies;
    }

    /**
     * 🚗 Arrêts inhabituels : repère les trajets avec des phases d'arrêt prolongé
     * (> 5 minutes à vitesse < 2 km/h en plein trajet), signe possible
     * de problème mécanique, d'incident ou de comportement suspect.
     */
    protected function detectUnusualStops(): array
    {
        $anomalies = [];

        // Trajets actifs ou récents (< 24h) avec plusieurs points à très faible vitesse
        $activeTrips = Trip::whereIn('statut', ['EN_COURS', 'TERMINE'])
            ->where('started_at', '>', now()->subDay())
            ->pluck('id');

        if ($activeTrips->isEmpty()) {
            return [];
        }

        // Trouver les trajets ayant ≥ 5 points consécutifs < 2 km/h sur ≥ 5 min
        $tripsWithStops = TripLocation::whereIn('trip_id', $activeTrips)
            ->where('vitesse_km_h', '<', 2)
            ->whereNotNull('vitesse_km_h')
            ->selectRaw('trip_id, COUNT(*) as slow_points, MIN(captured_at) as first_stop, MAX(captured_at) as last_stop')
            ->groupBy('trip_id')
            ->havingRaw('COUNT(*) >= 5')
            ->havingRaw('EXTRACT(EPOCH FROM (MAX(captured_at) - MIN(captured_at))) >= 300')
            ->get();

        foreach ($tripsWithStops as $row) {
            $trip = Trip::find($row->trip_id);
            if (! $trip) {
                continue;
            }
            $durationMin = round(($row->last_stop->timestamp - $row->first_stop->timestamp) / 60, 1);

            $anomalies[] = [
                'titre' => 'Arrêt prolongé détecté',
                'description' => "Le trajet #{$row->trip_id} présente un arrêt de {$durationMin} min "
                    . "({$row->slow_points} points GPS à vitesse < 2 km/h) "
                    . 'entre ' . $row->first_stop->format('H:i') . ' et ' . $row->last_stop->format('H:i') . '.',
                'gravite' => 'MOYENNE',
            ];
        }

        return $anomalies;
    }

    /**
     * 📵 Perte prolongée de mouvement : les trajets actifs dont la dernière
     * mise à jour GPS date de > 10 minutes — le téléphone est tombé en
     * panne, l'appareil est éteint, ou le transporteur a coupé le suivi.
     */
    protected function detectMovementLoss(): array
    {
        $anomalies = [];

        // Trajets EN_COURS sans mise à jour GPS depuis > 10 min
        $staleTrips = Trip::where('statut', 'EN_COURS')
            ->where('started_at', '<', now()->subMinutes(15))
            ->with('transporteur')
            ->get()
            ->filter(function (Trip $trip) {
                $lastLocation = $trip->locations()
                    ->orderByDesc('captured_at')
                    ->value('captured_at');

                return $lastLocation === null || $lastLocation->diffInMinutes(now()) >= 10;
            });

        foreach ($staleTrips as $trip) {
            $driver = $trip->transporteur;
            $driverName = $driver ? $driver->prenom . ' ' . $driver->nom : "transporteur #{$trip->transporteur_id}";
            $lastLoc = $trip->locations()->orderByDesc('captured_at')->first();
            $lastUpdate = $lastLoc ? $lastLoc->captured_at->diffInMinutes(now()) : 'jamais';

            $anomalies[] = [
                'titre' => 'Perte de signal GPS prolongée',
                'description' => "Le trajet #{$trip->id} ({$driverName}) n'a pas envoyé "
                    . "de position depuis {$lastUpdate} min. "
                    . 'Début du trajet: ' . $trip->started_at->format('H:i') . '.',
                'gravite' => 'ELEVEE',
            ];
        }

        return $anomalies;
    }

    /**
     * 🔄 Déviations d'itinéraire améliorées : compare le tracé réel
     * (actual_route_polyline) au tracé prévu (planned_route_polyline)
     * point par point et calcule la distance maximale de déviation.
     * Seuil : > 1 km de déviation maximale par rapport au trajet prévu.
     */
    protected function detectRouteDetours(): array
    {
        $anomalies = [];
        $routeService = app(RouteService::class);

        $deviationThreshold = 1.0; // km — déviation maximale acceptable

        $trips = Trip::where('statut', 'TERMINE')
            ->whereNotNull('planned_route_polyline')
            ->whereNotNull('actual_route_polyline')
            ->where('planned_route_polyline', '!=', '')
            ->where('actual_route_polyline', '!=', '')
            ->get();

        foreach ($trips as $trip) {
            $planned = $routeService->decodePolyline($trip->planned_route_polyline);
            $actual = $routeService->decodePolyline($trip->actual_route_polyline);

            if (count($planned) < 2 || count($actual) < 2) {
                continue;
            }

            $maxDeviation = 0.0;
            $worstPoint = null;

            foreach ($actual as $actualPoint) {
                $minDist = PHP_FLOAT_MAX;
                foreach ($planned as $plannedPoint) {
                    $dist = $routeService->haversine(
                        $actualPoint[0], $actualPoint[1],
                        $plannedPoint[0], $plannedPoint[1]
                    );
                    $minDist = min($minDist, $dist);
                }
                if ($minDist > $maxDeviation) {
                    $maxDeviation = $minDist;
                    $worstPoint = $actualPoint;
                }
            }

            if ($maxDeviation > $deviationThreshold) {
                $anomalies[] = [
                    'titre' => 'Déviation importante d\'itinéraire',
                    'description' => "Le trajet #{$trip->id} s'est écarté de "
                        . round($maxDeviation, 2) . " km du tracé prévu (seuil: {$deviationThreshold} km)"
                        . ($worstPoint
                            ? ' — point le plus éloigné: ' . round($worstPoint[0], 5) . ', ' . round($worstPoint[1], 5)
                            : '') . '.',
                    'gravite' => 'ELEVEE',
                ];
            }
        }

        return $anomalies;
    }

    /**
     * Vérifie en temps réel les anomalies d'un trajet actif à chaque
     * nouvelle position GPS. Crée un enregistrement AnomalyVerification
     * + notification push pour chaque anomalie détectée, et ce pour
     * CHAQUE partie du trajet (passager ET transporteur). Les deux
     * peuvent confirmer "normal" ou signaler un problème.
     * Sans réponse en 3 min → SOS automatique sur le non-répondant.
     */
    public function checkTripAnomalies(Trip $trip): array
    {
        $detected = [];

        // Les deux parties sont averties et facturées d'une réponse
        // indépendante : passager et transporteur (affecté dès le scan).
        $respondentIds = collect([$trip->passager_id, $trip->transporteur_id])
            ->filter()
            ->unique()
            ->values()
            ->all();

        // 1) Vitesse excessive
        $lastLocation = $trip->locations()->orderByDesc('captured_at')->first();
        if ($lastLocation && $lastLocation->vitesse_km_h && $lastLocation->vitesse_km_h > 120) {
            foreach ($respondentIds as $userId) {
                $detected[] = $this->createVerification(
                    $trip, $userId,
                    'SPEED',
                    "Vitesse excessive détectée : {$lastLocation->vitesse_km_h} km/h "
                        . 'à ' . $lastLocation->captured_at->format('H:i') . '.',
                    'ELEVEE'
                );
            }
        }

        // 2) Arrêt prolongé (> 5 min à vitesse < 2 km/h)
        $slowCount = $trip->locations()
            ->where('vitesse_km_h', '<', 2)
            ->whereNotNull('vitesse_km_h')
            ->where('captured_at', '>', now()->subMinutes(10))
            ->count();

        if ($slowCount >= 5) {
            $firstSlow = $trip->locations()
                ->where('vitesse_km_h', '<', 2)
                ->whereNotNull('vitesse_km_h')
                ->where('captured_at', '>', now()->subMinutes(10))
                ->orderBy('captured_at')
                ->value('captured_at');

            if ($firstSlow) {
                $durationMin = now()->diffInMinutes($firstSlow);
                foreach ($respondentIds as $userId) {
                    $detected[] = $this->createVerification(
                        $trip, $userId,
                        'STOP',
                        "Arrêt prolongé : {$durationMin} min sans mouvement "
                            . "({$slowCount} points GPS < 2 km/h).",
                        'MOYENNE'
                    );
                }
            }
        }

        // 3) Perte de signal GPS (> 10 min sans mise à jour)
        $lastLocTime = $trip->locations()->max('captured_at');
        if ($lastLocTime && Carbon::parse($lastLocTime)->diffInMinutes(now()) >= 10) {
            foreach ($respondentIds as $userId) {
                $detected[] = $this->createVerification(
                    $trip, $userId,
                    'MOVEMENT_LOSS',
                    "Perte de signal GPS : plus de position depuis "
                        . Carbon::parse($lastLocTime)->diffInMinutes(now()) . " min.",
                    'ELEVEE'
                );
            }
        }

        // 4) Déviation d'itinéraire (polyline comparison)
        if ($trip->planned_route_polyline && $lastLocation) {
            $routeService = app(RouteService::class);
            $planned = $routeService->decodePolyline($trip->planned_route_polyline);

            if (count($planned) >= 2) {
                $minDist = PHP_FLOAT_MAX;
                foreach ($planned as $pt) {
                    $d = $routeService->haversine(
                        (float) $lastLocation->latitude, (float) $lastLocation->longitude,
                        $pt[0], $pt[1]
                    );
                    $minDist = min($minDist, $d);
                }

                if ($minDist > 1.0) {
                    foreach ($respondentIds as $userId) {
                        $detected[] = $this->createVerification(
                            $trip, $userId,
                            'DETOUR',
                            "Déviation d'itinéraire : " . round($minDist, 2)
                                . " km du tracé prévu (seuil: 1 km).",
                            'ELEVEE'
                        );
                    }
                }
            }
        }

        return $detected;
    }

    /**
     * Crée un enregistrement de vérification d'anomalie + notification.
     * Ne crée pas de doublon si une vérification EN_ATTENTE du même type
     * existe déjà pour ce trajet ET ce utilisateur (chaque partie répond
     * de façon indépendante).
     */
    protected function createVerification(
        Trip $trip,
        int $userId,
        string $type,
        string $description,
        string $gravite,
    ): AnomalyVerification {
        $existing = AnomalyVerification::where('trip_id', $trip->id)
            ->where('user_id', $userId)
            ->where('anomaly_type', $type)
            ->where('statut', 'EN_ATTENTE')
            ->first();

        if ($existing) {
            return $existing;
        }

        $verification = AnomalyVerification::create([
            'trip_id' => $trip->id,
            'user_id' => $userId,
            'anomaly_type' => $type,
            'description' => $description,
            'gravite' => $gravite,
            'statut' => 'EN_ATTENTE',
        ]);

        Notification::create([
            'user_id' => $userId,
            'type' => 'ANOMALIE_VERIFICATION',
            'titre' => 'Anomalie détectée — vérification requise',
            'message' => $description . ' Confirmez si c\'est normal ou signalez un problème.',
        ]);

        return $verification;
    }

    protected function tripData(Trip $trip): array
    {
        return [
            'trajet_id' => $trip->id,
            'distance_km' => $trip->distance_km,
            'duree_secondes' => $trip->duration_seconds,
            'ecart_km' => $trip->deviation_km,
            'alerte_ecart' => $trip->deviation_alert,
            'destination' => $trip->destination_address,
            'method_fin' => $trip->end_method,
            'sos' => SosAlert::where('trip_id', $trip->id)->count(),
            'litiges' => Dispute::where('trip_id', $trip->id)->count(),
        ];
    }

    protected function roleData(User $user, string $role): array
    {
        return match ($role) {
            'transporteur' => [
                'trajets' => $user->tripsAsTransporteur()->where('statut', 'TERMINE')->count(),
                'passagers_transportes' => $user->tripsAsTransporteur()->distinct()->count(),
                'ecart_moyen_km' => round(
                    (float) $user->tripsAsTransporteur()->where('statut', 'TERMINE')->avg('deviation_km') ?? 0,
                    2,
                ),
                'sos_sur_trajets' => SosAlert::whereIn('trip_id', $user->tripsAsTransporteur()->pluck('id'))->count(),
            ],
            'gestionnaire' => [
                'dossiers' => $user->managerAssignments()->count(),
                'clotures' => $user->managerAssignments()->where('statut', 'CLOTURE')->count(),
                'temps_moyen_prise_min' => $this->avgMinutes('taken_at', 'assigned_at', $user),
            ],
            'admin' => [
                'total_trajets' => Trip::count(),
                'total_sos' => SosAlert::count(),
                'total_utilisateurs' => User::count(),
                'anomalies_signalees' => AiReport::where('type', 'ANOMALIE')->count(),
            ],
            default => [
                'trajets' => $user->tripsAsPassager()->where('statut', 'TERMINE')->count(),
                'distance_totale_km' => round(
                    (float) $user->tripsAsPassager()->where('statut', 'TERMINE')->sum('distance_km') ?? 0,
                    2,
                ),
                'sos' => SosAlert::where('passager_id', $user->id)->count(),
                'litiges' => Dispute::where('passager_id', $user->id)->count(),
            ],
        };
    }

    protected function avgMinutes(string $end, string $start, User $user): ?float
    {
        $rows = $user->managerAssignments()
            ->whereNotNull($end)
            ->whereNotNull($start)
            ->get([$start, $end]);

        if ($rows->isEmpty()) {
            return null;
        }

        $total = 0;
        foreach ($rows as $row) {
            $total += $row->$end->diffInMinutes($row->$start);
        }

        return round($total / $rows->count(), 1);
    }

    protected function fallbackTripSummary(array $d): string
    {
        $duree = isset($d['duree_secondes']) ? round($d['duree_secondes'] / 60) . ' min' : '—';
        $sos = $d['sos'] > 0 ? " {$d['sos']} alerte(s) SOS." : '';
        $ecart = $d['alerte_ecart'] ? " Écart d'itinéraire de {$d['ecart_km']} km détecté." : ' Itinéraire conforme au prévu.';

        return "Résumé du trajet #{$d['trajet_id']} : {$d['distance_km']} km en $duree."
            . "$ecart$sos";
    }

    protected function fallbackUserStats(User $user, string $role, array $d): string
    {
        $lines = ["Bilan {$role} (utilisateur #{$user->id}) :"];
        foreach ($d as $k => $v) {
            $lines[] = "- $k : $v";
        }

        return implode("\n", $lines);
    }
}
