<?php

namespace App\Http\Controllers;

use App\Models\LostItemReport;
use App\Models\Trip;
use App\Models\ManagerAssignment;
use App\Models\Notification;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class LostItemController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $reports = LostItemReport::with('trip', 'passager')
            ->where('passager_id', $request->user()->id)
            ->latest()
            ->paginate(15);

        return response()->json(['reports' => $reports]);
    }

    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'trip_id' => 'required|exists:trips,id',
            'objet' => 'required|string|max:150',
            'description' => 'nullable|string',
        ]);

        $trip = Trip::where('id', $data['trip_id'])
            ->where('passager_id', $request->user()->id)
            ->firstOrFail();

        $report = LostItemReport::create([
            'trip_id' => $trip->id,
            'passager_id' => $request->user()->id,
            'objet' => $data['objet'],
            'description' => $data['description'] ?? null,
            'statut' => 'SIGNALE',
        ]);

        $this->assignManager($report, $trip);

        return response()->json([
            'message' => 'Objet perdu signalé. Le signalement est lié au trajet ' . $trip->id . ' et au transporteur.',
            'report' => $report->load('trip'),
        ], 201);
    }

    public function update(Request $request, int $id): JsonResponse
    {
        $data = $request->validate([
            'statut' => 'sometimes|in:SIGNALE,EN_RECHERCHE,RETROUVE,RESTITUE,NON_RETROUVE,CLOTURE',
            'objet' => 'sometimes|string|max:150',
            'description' => 'sometimes|string',
        ]);

        $report = LostItemReport::where('id', $id)->where('passager_id', $request->user()->id)->firstOrFail();
        $report->update($data);

        return response()->json(['report' => $report->fresh('trip')]);
    }

    protected function assignManager(LostItemReport $report, Trip $trip): void
    {
        $manager = User::whereHas('roles', fn ($q) => $q->where('slug', 'gestionnaire'))
            ->withCount(['managerAssignments as ouvertes' => fn ($q) => $q->where('statut', '!=', 'CLOTURE')])
            ->orderBy('ouvertes')
            ->first();

        if ($manager) {
            ManagerAssignment::create([
                'manager_id' => $manager->id,
                'dossier_type' => 'OBJET_PERDU',
                'dossier_id' => $report->id,
                'statut' => 'ATTRIBUE',
            ]);

            Notification::create([
                'user_id' => $manager->id,
                'type' => 'DOSSIER',
                'titre' => 'Nouveau dossier objet perdu',
                'message' => 'Objet perdu signalé sur le trajet #' . $trip->id . ' — transporteur ' . $trip->transporteur_id,
            ]);
        }
    }
}