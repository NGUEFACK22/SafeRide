<?php

namespace App\Http\Controllers;

use App\Services\AiService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class AiController extends Controller
{
    public function __construct(
        private readonly AiService $ai,
    ) {
    }

    /**
     * Résumé / statistiques adaptés au rôle de l'utilisateur connecté.
     * ?refresh=1 force la régénération (sinon renvoie le dernier rapport récent).
     */
    public function summary(Request $request): JsonResponse
    {
        $user = $request->user();
        $refresh = $request->query('refresh') === '1';

        if (! $refresh) {
            $recent = \App\Models\AiReport::where('user_id', $user->id)
                ->where('type', 'STATISTIQUES')
                ->latest()
                ->first();

            if ($recent && $recent->created_at->gt(now()->subDay())) {
                return response()->json(['report' => $recent]);
            }
        }

        $report = $this->ai->userStats($user);

        return response()->json(['report' => $report]);
    }

    /**
     * Résumé hebdomadaire de l'utilisateur (semaine en cours, généré le dimanche
     * par la commande planifiée). ?refresh=1 force la régénération.
     */
    public function weekly(Request $request): JsonResponse
    {
        $user = $request->user();
        $refresh = $request->query('refresh') === '1';

        $report = \App\Models\AiReport::where('user_id', $user->id)
            ->where('type', 'RAPPORT_HEBDOMADAIRE')
            ->latest()
            ->first();

        $startOfWeek = now()->startOfWeek();

        if ($refresh || ! $report || $report->created_at->lt($startOfWeek)) {
            $report = $this->ai->weeklyReport($user);
        }

        return response()->json(['report' => $report]);
    }

    /**
     * Résumé d'un trajet (propriétaire ou transporteur).
     */
    public function tripSummary(Request $request, int $id): JsonResponse
    {
        $trip = \App\Models\Trip::where('id', $id)
            ->where(function ($q) use ($request) {
                $q->where('passager_id', $request->user()->id)
                  ->orWhere('transporteur_id', $request->user()->id);
            })
            ->firstOrFail();

        $report = \App\Models\AiReport::where('trip_id', $trip->id)
            ->where('type', 'RESUME_TRAJET')
            ->latest()
            ->first();

        if (! $report) {
            $report = $this->ai->tripSummary($trip);
        }

        return response()->json([
            'report' => $report,
            'insights' => $report->insights,
        ]);
    }

    /**
     * Anomalies détectées (gestionnaire / admin).
     */
    public function anomalies(Request $request): JsonResponse
    {
        $report = \App\Models\AiReport::where('type', 'ANOMALIE')->latest()->first();

        if (! $report || $report->created_at->lt(now()->subDay())) {
            $raw = $this->ai->detectAnomalies();
            $report = \App\Models\AiReport::create([
                'type' => 'ANOMALIE',
                'contenu' => 'Anomalies détectées par le moteur IA.',
                'generateur' => $this->ai->isEnabled() ? 'IA_SafeRide' : 'REGLE',
            ]);
            foreach ($raw as $a) {
                \App\Models\AiInsight::create(array_merge(['ai_report_id' => $report->id], $a));
            }
        }

        return response()->json([
            'report' => $report,
            'insights' => $report->insights,
        ]);
    }
}
