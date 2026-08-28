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
            'image' => 'nullable|file|image|mimes:jpeg,jpg,png|mimetypes:image/jpeg,image/png|max:10240',
            'image2' => 'nullable|file|image|mimes:jpeg,jpg,png|mimetypes:image/jpeg,image/png|max:10240',
            'images' => 'nullable|array|max:2',
            'images.*' => 'file|image|mimes:jpeg,jpg,png|mimetypes:image/jpeg,image/png|max:10240',
        ]);

        $trip = Trip::where('id', $data['trip_id'])
            ->where('passager_id', $request->user()->id)
            ->firstOrFail();

        $imageUrl = null;
        $imageUrl2 = null;
        if ($request->hasFile('image')) {
            $imageUrl = $request->file('image')->store('lost-items', 'public');
        }
        if ($request->hasFile('image2')) {
            $imageUrl2 = $request->file('image2')->store('lost-items', 'public');
        } elseif ($request->hasFile('images')) {
            $imgs = $request->file('images');
            if (is_array($imgs) && count($imgs) > 0 && ! $imageUrl) {
                $imageUrl = $imgs[0]->store('lost-items', 'public');
            }
            if (is_array($imgs) && count($imgs) > 1) {
                $imageUrl2 = $imgs[1]->store('lost-items', 'public');
            }
        }

        $report = LostItemReport::create([
            'trip_id' => $trip->id,
            'passager_id' => $request->user()->id,
            'objet' => $data['objet'],
            'description' => $data['description'] ?? null,
            'image_url' => $imageUrl,
            'image_url2' => $imageUrl2,
            'statut' => 'SIGNALE',
        ]);

        $this->assignManager($report, $trip);

        return response()->json([
            'message' => 'Objet perdu signalé. Le signalement est lié au trajet ' . $trip->id . ' et au transporteur.',
            'report' => $report->load('trip'),
            'chronology' => $this->reconstructChronology($report),
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

    /**
     * Reconstitue la chronologie : autres passagers ayant utilisé le même
     * véhicule entre la fin du trajet concerné et le signalement de l'objet.
     * Permet d'identifier qui a pu trouver/emporter l'objet perdu.
     */
    public function chronology(Request $request, int $id): JsonResponse
    {
        $report = LostItemReport::with('trip.vehicle')->findOrFail($id);

        return response()->json([
            'report_id' => $report->id,
            'vehicle_id' => $report->trip?->vehicle_id,
            'related_trips' => $this->reconstructChronology($report),
        ]);
    }

    protected function reconstructChronology(LostItemReport $report): array
    {
        $trip = $report->trip;
        if (! $trip || ! $trip->vehicle_id) {
            return [];
        }

        $from = $trip->ended_at ?? $trip->started_at;
        $to = $report->created_at;

        if (! $from || ! $to) {
            return [];
        }

        return Trip::with('passager')
            ->where('vehicle_id', $trip->vehicle_id)
            ->where('id', '!=', $trip->id)
            ->whereNotNull('ended_at')
            ->where('ended_at', '>=', $from)
            ->where('ended_at', '<=', $to)
            ->orderBy('ended_at')
            ->get()
            ->map(fn (Trip $t) => [
                'trip_id' => $t->id,
                'passager_id' => $t->passager_id,
                'passager_nom' => trim(($t->passager?->prenom ?? '') . ' ' . ($t->passager?->nom ?? '')) ?: null,
                'transporteur_id' => $t->transporteur_id,
                'ended_at' => $t->ended_at,
                'statut' => $t->statut,
            ])
            ->all();
    }
}