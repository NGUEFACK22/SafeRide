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
use Illuminate\Support\Facades\Cache;
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
                'sos_en_cours' => SosAlert::whereNotIn('statut', ['RESOLU', 'CLOTURE', 'FAUSSE_ALERTE'])->whereBetween('created_at', [$debut, $fin])->count(),
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
     *  - Écarts d'itinéraire répétés par un même transporteur
     *  - SOS vocaux non vérifiés
     *  - Vitesse excessive / arrêts inhabituels (GPS locations)
     *  - Perte prolongée de mouvement (trajets actifs sans update)
     *  - Déviations d'itinéraire améliorées (comparaison polyline)
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
     * Vitesse excessive : repère les locations où la vitesse > 120 km/h
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
     * Arrêts inhabituels : repère les trajets avec des phases d'arrêt prolongé
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
     * Perte prolongée de mouvement : les trajets actifs dont la dernière
     * mise à jour GPS date de > 10 minutes — le téléphone est tombé en
     * panne, l'appareil est éteint, ou le transporteur a coupé le suivi.
     */
    protected function detectMovementLoss(): array
    {
        $anomalies = [];

        // Trajets EN_COURS ou FIN_EN_ATTENTE sans mise à jour GPS depuis > 10 min
        $staleTrips = Trip::whereIn('statut', ['EN_COURS', 'FIN_EN_ATTENTE'])
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
     * Déviations d'itinéraire améliorées : compare le tracé réel
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
     * Sans réponse en 5 min → SOS automatique sur le non-répondant.
     */
    public function checkTripAnomalies(Trip $trip): array
    {
        $detected = [];

        // Vitesse et perte de signal : les DEUX parties sont averties et
        // répondent indépendamment. Déviation d'itinéraire et arrêt
        // prolongé : c'est le PASSAGER qu'on interroge (« le transporteur
        // n'a pas respecté l'itinéraire, tout va bien ? »), et seulement
        // quand la situation PERSISTE (5 min hors tracé / 10 min immobile)
        // — un simple ralentissement ou un détour de 2 min n'alarme personne.
        $bothParties = collect([$trip->passager_id, $trip->transporteur_id])
            ->filter()
            ->unique()
            ->values()
            ->all();

        // 1) Vitesse excessive
        $lastLocation = $trip->locations()->orderByDesc('captured_at')->first();
        if ($lastLocation && $lastLocation->vitesse_km_h && $lastLocation->vitesse_km_h > 120) {
            foreach ($bothParties as $userId) {
                $detected[] = $this->createVerification(
                    $trip, $userId,
                    'SPEED',
                    "Vitesse excessive détectée : {$lastLocation->vitesse_km_h} km/h "
                        . 'à ' . $lastLocation->captured_at->format('H:i') . '.',
                    'ELEVEE'
                );
            }
        }

        // 2) Arrêt prolongé (> 10 min à vitesse < 2 km/h) — question au passager.
        $slowStreak = $trip->locations()
            ->where('vitesse_km_h', '<', 2)
            ->whereNotNull('vitesse_km_h')
            ->where('captured_at', '>', now()->subMinutes(20))
            ->orderBy('captured_at')
            ->get();
        $firstSlow = $slowStreak->first();

        if ($firstSlow && $firstSlow->captured_at->diffInMinutes(now()) >= self::STOP_NOTIF_MINUTES
            && $slowStreak->count() >= 5 && $trip->passager_id) {
            $durationMin = $firstSlow->captured_at->diffInMinutes(now());
            $detected[] = $this->createVerification(
                $trip, $trip->passager_id,
                'STOP',
                "Notre système a constaté que le véhicule est arrêté au même endroit depuis {$durationMin} "
                    . 'min pendant votre trajet. Tout va bien ? Sinon, signalez un problème : l\'alerte SOS partira immédiatement.',
                'MOYENNE'
            );
        }

        // 3) Perte de signal GPS (> seuil sans mise à jour) — repli sur
        // started_at si aucune position n'a jamais été reçue.
        $lastLocTime = $trip->locations()->max('captured_at');
        $gpsReference = $lastLocTime ? Carbon::parse($lastLocTime) : $trip->started_at;
        if ($gpsReference && $gpsReference->diffInMinutes(now()) >= self::MOVEMENT_LOSS_MINUTES) {
            foreach ($bothParties as $userId) {
                $detected[] = $this->createVerification(
                    $trip, $userId,
                    'MOVEMENT_LOSS',
                    "Perte de signal GPS : plus de position depuis "
                        . $gpsReference->diffInMinutes(now()) . " min.",
                    'ELEVEE'
                );
            }
        }

        // 4) Déviation d'itinéraire — constatée ET persistée 5 min (le
        // transporteur n'est pas revenu sur le tracé) => fenêtre au passager.
        if ($trip->planned_route_polyline && $lastLocation) {
            $routeService = app(RouteService::class);
            $planned = $routeService->decodePolyline($trip->planned_route_polyline);

            if (count($planned) >= 2) {
                $minDist = $this->distanceToPlanned($planned, $lastLocation->latitude, $lastLocation->longitude);

                if ($minDist > 1.0 && $trip->passager_id) {
                    // La déviation est-elle ancienne (≥ 5 min) ? On vérifie
                    // qu'un point hors tracé a été capturé il y a 5 min ou
                    // plus : le transporteur n'est pas revenu sur l'itinéraire.
                    $persisted = $trip->locations()
                        ->where('captured_at', '>=', now()->subMinutes(30))
                        ->where('captured_at', '<=', now()->subMinutes(self::DETOUR_PERSIST_MINUTES))
                        ->get()
                        ->contains(fn ($l) => $this->distanceToPlanned($planned, $l->latitude, $l->longitude) > 1.0);

                    if ($persisted) {
                        $detected[] = $this->createVerification(
                            $trip, $trip->passager_id,
                            'DETOUR',
                            "Le transporteur n'a pas respecté l'itinéraire prévu (" . round($minDist, 1)
                                . " km de l'écart, constant depuis plus de "
                                . self::DETOUR_PERSIST_MINUTES . ' min). Est-ce que tout va bien ? '
                                . 'Sinon signalez un problème : l\'alerte SOS partira immédiatement.',
                            'ELEVEE'
                        );
                    }
                }
            }
        }

        return $detected;
    }

    /**
     * Distance (km) minimale entre une position et le tracé planifié décodé.
     */
    protected function distanceToPlanned(array $planned, float|string $lat, float|string $lng): float
    {
        $routeService = app(RouteService::class);
        $min = PHP_FLOAT_MAX;
        foreach ($planned as $pt) {
            $min = min($min, $routeService->haversine((float) $lat, (float) $lng, $pt[0], $pt[1]));
        }

        return $min;
    }

    /**
     * La situation d'origine d'une vérification est-elle toujours en cours ?
     * Utilisé par l'escalade : pas de rappel si le transporteur est revenu
     * sur l'itinéraire ou si le véhicule est reparti entre-temps.
     */
    public function situationOngoing(AnomalyVerification $verification): bool
    {
        $trip = $verification->trip;
        if (! $trip) {
            return true; // trajet supprimé : on considère que rien ne rassure.
        }
        $last = $trip->locations()->orderByDesc('captured_at')->first();

        return match ($verification->anomaly_type) {
            'DETOUR' => $trip->planned_route_polyline && $last
                ? $this->distanceToPlanned(
                    app(RouteService::class)->decodePolyline($trip->planned_route_polyline),
                    $last->latitude,
                    $last->longitude,
                ) > 1.0
                : true,
            'STOP' => $last ? (float) ($last->vitesse_km_h ?? 0) < 2 : true,
            default => true,
        };
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

    /**
     * Seuil de perte de signal GPS (min) : au-delà sans aucune position,
     * une vérification interactive MOVEMENT_LOSS est créée pour les deux
     * parties (non-réponse → SOS automatique après timeout).
     */
    public const MOVEMENT_LOSS_MINUTES = 10;

    /**
     * Le transporteur doit être resté hors itinéraire pendant au moins ce
     * délai (min) pour qu'on NOTIFIE le passager : une brève déviation
     * (un embouteillage, un tourne-à-droite) n'alarme personne.
     */
    public const DETOUR_PERSIST_MINUTES = 5;

    /**
     * Arrêt immobilisé (min) au même endroit avant de demander au passager
     * si tout va bien.
     */
    public const STOP_NOTIF_MINUTES = 10;

    /**
     * Watchdog planifié (à appeler chaque minute) : détecte la perte de
     * signal GPS côté SERVEUR. La détection "normale" de checkTripAnomalies()
     * ne vit que dans POST /trips/{trip}/locations — or un téléphone éteint,
     * à plat ou confisqué ne poste plus rien : sans ce watchdog, le cas le
     * plus critique (plus de GPS du tout) ne serait JAMAIS vérifié.
     *
     * createVerification() déduplique (même trajet, utilisateur, type et
     * statut EN_ATTENTE) : appeler cette commande en boucle ne crée pas de
     * doublons, et le timeout de non-réponse (anomaly:check-timeouts) prend
     * ensuite le relais pour le SOS automatique.
     */
    public function checkStaleTrips(): int
    {
        $created = 0;

        // Un trajet EN_COURS ou FIN_EN_ATTENTE est suspect dès qu'aucune position n'est arrivée
        // depuis MOVEMENT_LOSS_MINUTES (référence : dernière position, à
        // défaut l'heure de départ si le GPS n'a jamais accroché).
        Trip::whereIn('statut', ['EN_COURS', 'FIN_EN_ATTENTE'])
            ->where('started_at', '<', now()->subMinutes(self::MOVEMENT_LOSS_MINUTES))
            ->chunkById(50, function ($trips) use (&$created) {
                foreach ($trips as $trip) {
                    $lastLocTime = $trip->locations()->max('captured_at');
                    $reference = $lastLocTime ? Carbon::parse($lastLocTime) : $trip->started_at;

                    if (! $reference || $reference->diffInMinutes(now()) < self::MOVEMENT_LOSS_MINUTES) {
                        continue;
                    }

                    $minutes = $reference->diffInMinutes(now());
                    $respondentIds = collect([$trip->passager_id, $trip->transporteur_id])
                        ->filter()->unique()->values()->all();

                    foreach ($respondentIds as $userId) {
                        $before = AnomalyVerification::where('trip_id', $trip->id)
                            ->where('user_id', $userId)
                            ->where('anomaly_type', 'MOVEMENT_LOSS')
                            ->where('statut', 'EN_ATTENTE')
                            ->exists();

                        $this->createVerification(
                            $trip, $userId,
                            'MOVEMENT_LOSS',
                            "Perte de signal GPS : plus de position depuis {$minutes} min.",
                            'ELEVEE'
                        );

                        if (! $before) {
                            $created++;
                        }
                    }
                }
            });

        return $created;
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

    /**
     * PRÉDICTION — analyse de l'historique de l'utilisateur pour anticiper :
     *  1. ses zones fréquentes (cluster des points de départ/d'arrivée) ;
     *  2. le climat actuel et prévu (pluie) sur ces zones (Open-Meteo) ;
     *  3. les créneaux à bouchons — fusion des pics observés dans SES trajets
     *     (densité horaire + durées) et des pics structurels (heure de pointe) ;
     *  4. des conseils concrets pour les éviter.
     * Narrative enrichie par le LLM si disponible, repli déterministe sinon.
     * Renvoie ['report' => AiReport, 'prediction' => array structuré pour l'UI].
     */
    public function predict(User $user): array
    {
        $data = $this->predictionData($user);
        $prediction = $this->buildPrediction($data);

        $system = "Tu es l'assistant IA prédictif de SafeRide (trajets partagés au Cameroun). "
            . "À partir des données fournies (zones fréquentes de l'utilisateur, climat Open-Meteo, "
            . "densité horaire de ses trajets, pics de bouchons calculés), rédige en français un "
            . "briefing concret de 5 à 8 lignes : climat à attendre sur ses zones, heures exactes à "
            . "éviter, et 2-3 conseils actionnables pour les contourner. Pas de généralités, only "
            . "des recommandations basées sur les données. Termine par une phrase d'encouragement.";

        $prompt = "Données de prédiction pour {$user->prenom} {$user->nom} :\n"
            . json_encode($prediction, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE);

        $contenu = $this->complete($system, $prompt)
            ?? $this->fallbackPrediction($prediction);

        $report = AiReport::create([
            'type' => 'PREDICTION',
            'contenu' => $contenu,
            'user_id' => $user->id,
            'generateur' => $this->isEnabled() ? 'IA_SafeRide' : 'REGLE',
        ]);

        return ['report' => $report, 'prediction' => $prediction];
    }

    /**
     * Phrase de refus exacte pour toute question hors périmètre SafeRide.
     */
    public const HORS_DOMAINE_REPONSE = 'Cette question n\'est pas dans mes compétences. Je réponds uniquement aux questions liées à SafeRide : trajets, réservations, sécurité (SOS, QR), profil, prédiction de trafic…';

    /**
     * Termes qui rattachent une question à la plateforme (pré-filtre rapide,
     * accents ignorés). Aucun terme trouvé => refus immédiat sans appel LLM.
     */
    protected const PLATEFORME_TERMES = [
        'trajet', 'course', 'reserv', 'commande', 'sos', 'urgence', 'assistance',
        'qr', 'verif', 'identite', 'profil', 'compte', 'inscription', 'connexion',
        'mot de passe', 'password', 'prediction', 'bouchon', 'embouteill', 'climat',
        'meteo', 'prix', 'tarif', 'paiement', 'facture', 'securite', 'partage',
        'note', 'evaluation', 'etoile', 'transporteur', 'chauffeur', 'passager',
        'gestionnaire', 'admin', 'application', 'app ', 'saferide', 'destination',
        'itineraire', 'annul', 'signaler', 'plainte', 'litige', 'voice', 'voie ',
        'localisation', 'gps', 'carte', 'douala', 'region', 'vehicule', 'voiture',
        'moto', 'bus', 'adresse', 'telephon', 'email', 'mail', 'notifications',
    ];

    /**
     * Répond à une question de l'utilisateur — UNIQUEMENT sur SafeRide et son
     * activité. Hors périmètre : message de refus (jamais de réponse générale).
     *
     * @return array{reponse: string, hors_domaine: bool, generateur: string}
     */
    public function ask(User $user, string $question): array
    {
        $q = mb_strtolower(trim($question));
        $qFold = $this->foldFr($q);

        // Salutations et politesse : toujours bienvenues (c'est la base d'un
        // chat), même si le reste doit rester dans le périmètre SafeRide.
        if ($this->estSalutation($qFold)) {
            $heure = (int) now()->format('G');
            $formule = $heure < 12 ? 'Bonjour' : ($heure < 18 ? 'Bon après-midi' : 'Bonsoir');

            return [
                'reponse' => "$formule {$user->prenom} ! Je suis l'assistant SafeRide. "
                    .'Je peux vous aider sur les trajets, la réservation, le QR de vérification, '
                    .'le bouton SOS, votre profil vérifié et l\'ANALYSE du trafic. '
                    .'Que puis-je faire pour vous ?',
                'hors_domaine' => false,
                'generateur' => 'REGLE',
            ];
        }

        // Remerciements : réponse courte et chaleureuse.
        if (preg_match('/merci|remerc/', $qFold) && mb_strlen($qFold) < 40) {
            return [
                'reponse' => 'Avec plaisir ! Bonne route avec SafeRide.',
                'hors_domaine' => false,
                'generateur' => 'REGLE',
            ];
        }

        // Pré-filtre : aucune trace de la plateforme => refus sans dépenser l'IA.
        $lieePlateforme = false;
        foreach (self::PLATEFORME_TERMES as $terme) {
            if (str_contains($qFold, $terme)) {
                $lieePlateforme = true;
                break;
            }
        }
        if (! $lieePlateforme) {
            return [
                'reponse' => self::HORS_DOMAINE_REPONSE,
                'hors_domaine' => true,
                'generateur' => 'REGLE',
            ];
        }

        $role = $user->roles()->first()?->slug ?? 'passager';

        if ($this->isEnabled()) {
            $system = "Tu es l'assistant IA de SafeRide, une application camerounaise de trajets "
                ."partagés sécurisés (rôle de l'utilisateur : {$role}). Fonctions de la plateforme : "
                .'réservation de trajet (sélection départ/destination à Douala, estimation du prix), '
                .'suivi GPS en temps réel, QR vérifié à chaque montée, bouton SOS URGENCE (alerte '
                .'secours + contacts), bouton ANALYSE (heures de bouchons, climat des zones '
                .'fréquentes, conseils), profil avec vérification d\'identité (badge IDENTITÉ '
                .'VÉRIFIÉE) et e-mail, notation en étoiles des trajets, partage de trajet, assistant '
                .'vocal. RÈGLE ABSOLUE : si la question ne concerne pas SafeRide ou l\'une de ces '
                .'fonctions, répond EXACTEMENT : « '
                .self::HORS_DOMAINE_REPONSE
                .' » sans rien ajouter d\'autre. Sinon réponds en français, en 2 à 6 phrases '
                .'concrètes, avec les étapes s\'il y en a.';

            $answer = $this->complete($system, "Question de {$user->prenom} : {$question}");

            if ($answer !== null) {
                $refuse = str_contains($this->foldFr(mb_strtolower($answer)), 'pas dans mes competences');

                return [
                    'reponse' => $refuse ? self::HORS_DOMAINE_REPONSE : trim($answer),
                    'hors_domaine' => $refuse,
                    'generateur' => 'IA_SafeRide',
                ];
            }
        }

        // Repli déterministe (IA désactivée ou indisponible).
        return [
            'reponse' => $this->fallbackAsk($qFold),
            'hors_domaine' => false,
            'generateur' => 'REGLE',
        ];
    }

    /** Réponses standard par sujet (IA non configurée). */
    protected function fallbackAsk(string $q): string
    {
        return match (true) {
            (bool) preg_match('/reserv|commande|nouveau trajet|comment.*trajet/', $q)
                => 'Pour réserver : allez sur l\'accueil, choisissez votre départ et votre destination dans la liste de Douala, validez — le prix estimé s\'affiche, puis un transporteur confirmé vous prend en charge avec QR vérifié.',
            (bool) preg_match('/sos|urgence| secours|alarme/', $q)
                => 'Le bouton SOS URGENCE (écran accueil) alerte immédiatement vos contacts de secours et la plateforme avec votre position GPS en direct. En cas de danger, appuyez longuement et gardez le téléphone avec vous.',
            (bool) preg_match('/qr|code|verifier.*mont|montee/', $q)
                => 'Le QR de vérification est régénéré à chaque montée : le passager le montre et le transporteur le scanne pour confirmer que ce sont bien les personnes réservées. Sans QR validé, le trajet ne démarre pas.',
            (bool) preg_match('/verif|identite|badge|profil|compte|inscription|connexion|mot de passe|email|e-mail/', $q)
                => 'Votre profil affiche le badge IDENTITÉ VÉRIFIÉE dès que votre pièce et votre e-mail sont validés. Pour revérifier : Profil → Vérifier mon identité ; pour l\'e-mail : Profil → Renvoyer la vérification.',
            (bool) preg_match('/prediction|bouchon|embouteill|meteo|climat|trafic/', $q)
                => 'Le bouton ANALYSE analyse vos trajets de la semaine : il vous donne les heures probables de bouchons, les créneaux fluides et le climat sur les zones que vous fréquentez le plus, avec des conseils pour éviter les pics.',
            (bool) preg_match('/note|evaluation|etoile|litige|plainte|signaler/', $q)
                => 'À la fin d\'un trajet, notez-le de 1 à 5 étoiles avec un commentaire. Un problème ? Signalez-le depuis le détail du trajet : le litige est examiné par la gestion.',
            (bool) preg_match('/prix|tarif|paiement|facture|commission/', $q)
                => 'Le prix est estimé avant la réservation selon la distance et la destination choisie. Le paiement se règle avec le transporteur ; une facture détaillée reste disponible dans l\'historique.',
            (bool) preg_match('/partage|localisation|gps|carte|suivi/', $q)
                => 'Le partage de trajet permet à vos contacts de suivre votre position GPS en direct pendant la course, jusqu\'à l\'arrivée. Activez-le depuis l\'écran du trajet en cours.',
            default => 'Je peux vous guider sur : réserver un trajet, le QR de vérification, le bouton SOS, la vérification d\'identité du profil, le bouton ANALYSE, les notes et litiges. Précisez votre question.',
        };
    }

    /** Minuscules + accents retirés (aligné sur le fold du mobile). */
    protected function foldFr(string $s): string
    {
        return strtr($s, [
            'á' => 'a', 'à' => 'a', 'â' => 'a', 'ä' => 'a', 'é' => 'e', 'è' => 'e',
            'ê' => 'e', 'ë' => 'e', 'í' => 'i', 'ì' => 'i', 'î' => 'i', 'ï' => 'i',
            'ó' => 'o', 'ò' => 'o', 'ô' => 'o', 'ö' => 'o', 'ú' => 'u', 'ù' => 'u',
            'û' => 'u', 'ü' => 'u', 'ç' => 'c', 'ñ' => 'n',
        ]);
    }

    /** Message de pure courtoisie (salutation) — jamais une vraie question. */
    protected function estSalutation(string $qFold): bool
    {
        // Formules connues, et messages très courts (≤ 3 mots) qui ne peuvent
        // pas être une question hors périmètre.
        if (preg_match('/\b(bonjour|bonsoir|salut|hello|hey|coucou|yo|bjr|slt|good (morning|evening|afternoon))\b/', $qFold)) {
            return true;
        }

        return mb_strlen($qFold) < 25 && preg_match('/^(a(la)?|comment (ca|ça|vas|allez)|ca va|vous vas|bienvenue|hi)\b/', $qFold);
    }

    /**
     * Agrège l'historique de l'utilisateur : ses 3 zones les plus fréquentes
     * (cluster grille ~1,1 km via arrondi 2 décimales), la densité horaire de
     * ses départs, et la durée moyenne par tranche horaire.
     */
    protected function predictionData(User $user): array
    {
        $role = $user->roles()->first()?->slug ?? 'passager';
        $trajets = $role === 'transporteur'
            ? $user->tripsAsTransporteur()->where('statut', 'TERMINE')->get()
            : $user->tripsAsPassager()->where('statut', 'TERMINE')->get();

        // 1. Clusters de zones de départ (arrondi 0.01° ≈ 1,1 km).
        $clusters = [];
        foreach ($trajets as $t) {
            if ($t->start_latitude === null || $t->start_longitude === null) {
                continue;
            }
            $key = round((float) $t->start_latitude, 2) . ',' . round((float) $t->start_longitude, 2);
            $clusters[$key]['count'] = ($clusters[$key]['count'] ?? 0) + 1;
            $clusters[$key]['lat'] = $clusters[$key]['lat'] ?? (float) $t->start_latitude;
            $clusters[$key]['lng'] = $clusters[$key]['lng'] ?? (float) $t->start_longitude;
            if ($t->destination_address && empty($clusters[$key]['label'])) {
                $clusters[$key]['label'] = $t->destination_address;
            }
            $clusters[$key]['hours'][(int) ($t->started_at?->hour ?? -1)] =
                ($clusters[$key]['hours'][(int) ($t->started_at?->hour ?? -1)] ?? 0) + 1;
        }
        arsort($clusters);
        $topZones = array_slice($clusters, 0, 3, true);

        // 2. Densité horaire globale + durée moyenne par heure (pics observés).
        $densite = array_fill(0, 24, 0);
        $dureesParHeure = [];
        foreach ($trajets as $t) {
            $h = (int) ($t->started_at?->hour ?? -1);
            if ($h < 0) {
                continue;
            }
            $densite[$h]++;
            if ($t->duration_seconds) {
                $dureesParHeure[$h][] = $t->duration_seconds / 60;
            }
        }
        $dureeMoyenneParHeure = [];
        foreach ($dureesParHeure as $h => $vals) {
            $dureeMoyenneParHeure[$h] = round(array_sum($vals) / count($vals));
        }

        // 3. Climat sur les zones fréquentes (Open-Meteo, gratuit, sans clé).
        $climats = [];
        foreach ($topZones as $key => $z) {
            $climats[$key] = $this->fetchWeather((float) $z['lat'], (float) $z['lng']);
        }

        return [
            'role' => $role,
            'nb_trajets_analyses' => $trajets->count(),
            'zones' => $topZones,
            'densite_horaire' => $densite,
            'duree_moyenne_par_heure' => $dureeMoyenneParHeure,
            'climats' => $climats,
        ];
    }

    /**
     * Transforme les données brutes en prédictions prêtes pour l'UI :
     * pics de bouchons (observés + structurels Cameroun), climat, conseils.
     */
    protected function buildPrediction(array $data): array
    {
        // Pics structurels heure de pointe (Douala/Yaoundé) : matin 7-9, soir 17-19.
        $structurels = [7, 8, 17, 18];
        $densite = $data['densite_horaire'];

        // Pics observés : heures où l'utilisateur part le PLUS souvent.
        arsort($densite);
        $observ = array_slice(array_keys($densite), 0, 2, true);

        // Fusion des deux sources (structurels + habitudes propres), bornée 5h-22h.
        $creneaux = $structurels;
        foreach ($observ as $h) {
            if (! in_array($h, $creneaux, true) && $h >= 5 && $h <= 22) {
                $creneaux[] = $h;
            }
        }
        sort($creneaux);

        // Heures « fluides » : 3 h hors pics avec de l'activité observée (sinon milieu de journée).
        $fluides = [];
        for ($h = 5; $h <= 22 && count($fluides) < 3; $h++) {
            if (! in_array($h, $creneaux, true)) {
                $fluides[] = $h;
            }
        }

        $climats = [];
        foreach ($data['climats'] as $key => $c) {
            if (! $c) {
                continue;
            }
            $climats[] = [
                'zone' => $key,
                'temperature_c' => $c['temperature_2m'] ?? null,
                'ressenti_c' => $c['apparent_temperature'] ?? null,
                'pluie_prob' => $c['precipitation_probability'] ?? null,
                'code_wmo' => $c['weather_code'] ?? null,
                'description' => $this->weatherFr((int) ($c['weather_code'] ?? 0)),
                'vent_km_h' => $c['wind_speed_10m'] ?? null,
            ];
        }

        $conseils = $this->buildAdvice($creneaux, $fluides, $climats);

        return [
            'genere_le' => now()->format('d/m/Y H:i'),
            'nb_trajets_analyses' => $data['nb_trajets_analyses'],
            'heures_bouchons' => array_map(fn ($h) => sprintf('%02dh00', $h), $creneaux),
            'heures_fluides' => array_map(fn ($h) => sprintf('%02dh00', $h), $fluides),
            'zones_frequentes' => array_map(fn ($k, $z) => [
                'libelle' => $z['label'] ? $k : ('Zone ' . $k),
                'trajets' => $z['count'],
            ], array_keys($data['zones']), $data['zones']),
            'climats' => $climats,
            'conseils' => $conseils,
        ];
    }

    /**
     * Conseils concrets dérivés des pics + climat (pluie = itinéraires et
     * horaires modifiés, les chaussées glissantes rallongent les trajets).
     */
    protected function buildAdvice(array $pics, array $fluides, array $climats): array
    {
        $advice = [];
        if ($pics && $fluides) {
            $advice[] = 'Évitez de partir entre ' . implode(', ', array_map(fn ($h) => sprintf('%02dh', $h), $pics))
                . ' — privilégiez ' . implode(' ou ', array_map(fn ($h) => sprintf('%02dh', $h), array_slice($fluides, 0, 2))) . '.';
        }
        $pluvieux = array_filter($climats, fn ($c) => ($c['pluie_prob'] ?? 0) >= 50);
        if ($pluvieux) {
            $advice[] = 'Pluie attendue (' . max(array_column($pluvieux, 'pluie_prob')) . '%) : partez 20 min plus tôt, les chaussées glissantes ralentissent le trafic.';
        } else {
            $advice[] = 'Pas de pluie prévue : conditions de circulation normales sur vos zones.';
        }
        $advice[] = 'Activez le partage de trajet et le QR vérifié : SafeRide surveille l\'itinéraire en temps réel.';

        return $advice;
    }

    /**
     * Récupère la météo Open-Meteo (gratuit, sans clé) pour une position.
     * 6 min de cache par 0.01° pour ne pas harceler l'API.
     */
    protected function fetchWeather(float $lat, float $lng): ?array
    {
        $key = 'openmeteo:' . round($lat, 2) . ':' . round($lng, 2);

        return Cache::remember($key, 360, function () use ($lat, $lng) {
            try {
                $response = Http::timeout(6)->get('https://api.open-meteo.com/v1/forecast', [
                    'latitude' => $lat,
                    'longitude' => $lng,
                    'current' => 'temperature_2m,apparent_temperature,precipitation_probability,weather_code,wind_speed_10m',
                    'timezone' => 'Africa/Douala',
                ]);

                return $response->successful() ? ($response->json('current') ?: null) : null;
            } catch (\Throwable $e) {
                return null;
            }
        });
    }

    /** Libellé météo FR d'un code WMO (aligné sur le mobile WeatherService). */
    protected function weatherFr(int $code): string
    {
        return match (true) {
            $code === 0 => 'Ciel dégagé',
            $code <= 2 => 'Partiellement nuageux',
            $code === 3 => 'Couvert',
            $code <= 48 => 'Brouillard',
            $code <= 57 => 'Bruine',
            $code <= 67 => 'Pluie',
            $code <= 77 => 'Neige',
            $code <= 82 => 'Averses',
            $code <= 99 => 'Orages',
            default => 'Variable',
        };
    }

    protected function fallbackPrediction(array $p): string
    {
        $lines = ["Analyse SafeRide (gérée par règles, {$p['genere_le']}) :"];
        if ($p['zones_frequentes']) {
            $zones = implode(', ', array_map(fn ($z) => $z['libelle'] . ' (' . $z['trajets'] . ' trajets)', $p['zones_frequentes']));
            $lines[] = "- Vos zones fréquentes : $zones.";
        }
        $lines[] = '- Heures à bouchons probables : ' . (implode(', ', $p['heures_bouchons']) ?: '—') . '.';
        $lines[] = '- Créneaux fluides : ' . (implode(', ', $p['heures_fluides']) ?: '—') . '.';
        foreach ($p['climats'] as $c) {
            $pluie = $c['pluie_prob'] !== null ? ", pluie {$c['pluie_prob']}%" : '';
            $lines[] = "- Climat zone {$c['zone']} : {$c['description']}, " . ($c['temperature_c'] ?? '—') . "°C{$pluie}.";
        }
        foreach ($p['conseils'] as $conseil) {
            $lines[] = "- $conseil";
        }

        return implode("\n", $lines);
    }
}
