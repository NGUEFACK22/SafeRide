<?php

namespace App\Http\Controllers;

use App\Models\Dispute;
use App\Models\Trip;
use App\Models\ManagerAssignment;
use App\Models\Notification;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class DisputeController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $disputes = Dispute::with('trip', 'passager', 'transporteur')
            ->where('passager_id', $request->user()->id)
            ->orWhere('transporteur_id', $request->user()->id)
            ->latest()
            ->paginate(15);

        return response()->json(['disputes' => $disputes]);
    }

    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'trip_id' => 'required|exists:trips,id',
            'motif' => 'required|string|max:255',
            'description' => 'nullable|string',
        ]);

        $trip = Trip::findOrFail($data['trip_id']);

        $isParty = $trip->passager_id === $request->user()->id || $trip->transporteur_id === $request->user()->id;
        if (! $isParty) {
            return response()->json(['message' => 'Vous ne participez pas à ce trajet'], 403);
        }

        $dispute = Dispute::create([
            'trip_id' => $trip->id,
            'passager_id' => $trip->passager_id === $request->user()->id ? $request->user()->id : $trip->passager_id,
            'transporteur_id' => $trip->transporteur_id === $request->user()->id ? $request->user()->id : $trip->transporteur_id,
            'motif' => $data['motif'],
            'description' => $data['description'] ?? null,
            'statut' => 'OUVERT',
        ]);

        $this->assignManager($dispute, $trip);

        return response()->json([
            'message' => 'Litige ouvert. Un gestionnaire va être attribué.',
            'dispute' => $dispute->load('trip'),
        ], 201);
    }

    protected function assignManager(Dispute $dispute, Trip $trip): void
    {
        $manager = User::whereHas('roles', fn ($q) => $q->where('slug', 'gestionnaire'))
            ->withCount(['managerAssignments as ouvertes' => fn ($q) => $q->where('statut', '!=', 'CLOTURE')])
            ->orderBy('ouvertes')
            ->first();

        if ($manager) {
            ManagerAssignment::create([
                'manager_id' => $manager->id,
                'dossier_type' => 'LITIGE',
                'dossier_id' => $dispute->id,
                'statut' => 'ATTRIBUE',
            ]);

            Notification::create([
                'user_id' => $manager->id,
                'type' => 'DOSSIER',
                'titre' => 'Nouveau dossier litige',
                'message' => 'Litige ouvert sur le trajet #' . $trip->id . ' — motif : ' . $dispute->motif,
            ]);
        }
    }
}