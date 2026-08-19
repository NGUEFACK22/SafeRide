<?php

namespace App\Services;

use App\Models\AiInsight;
use App\Models\AiReport;
use App\Models\Dispute;
use App\Models\ManagerAssignment;
use App\Models\SosAlert;
use App\Models\Trip;
use App\Models\User;
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
     * Renvoie des données brutes ; la persistance se fait sous un AiReport ANOMALIE.
     */
    public function detectAnomalies(): array
    {
        $anomalies = [];

        // Transporteurs avec écarts répétés
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
                    . "{$row->c} trajets avec écart important.",
                'gravite' => 'ELEVEE',
            ];
        }

        // SOS non vérifiés
        $unverified = SosAlert::where('declenchement', 'VOCAL')
            ->where('statut', 'VERIFICATION')
            ->count();

        if ($unverified > 0) {
            $anomalies[] = [
                'titre' => 'Alertes SOS vocales non vérifiées',
                'description' => "$unverified alerte(s) SOS vocale(s) en attente de vérification.",
                'gravite' => 'MOYENNE',
            ];
        }

        return $anomalies;
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
