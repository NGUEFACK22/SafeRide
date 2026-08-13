<?php

namespace App\Http\Controllers;

use App\Models\Dispute;
use App\Models\IdentityVerification;
use App\Models\LostItemReport;
use App\Models\ManagerAssignment;
use App\Models\SosAlert;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class ManagerController extends Controller
{
    public function dashboard(Request $request): JsonResponse
    {
        $manager = $request->user();

        $assignments = ManagerAssignment::with(['manager', 'dossier'])
            ->where('manager_id', $manager->id)
            ->get();

        $open = $assignments->where('statut', '!=', 'CLOTURE')->count();
        $closed = $assignments->where('statut', 'CLOTURE')->count();
        $byType = $assignments->groupBy('dossier_type')->map->count();

        return response()->json([
            'open' => $open,
            'closed' => $closed,
            'by_type' => $byType,
            'total' => $assignments->count(),
        ]);
    }

    public function myAssignments(Request $request): JsonResponse
    {
        $assignments = ManagerAssignment::with('dossier')
            ->where('manager_id', $request->user()->id)
            ->latest()
            ->paginate(20);

        return response()->json(['assignments' => $assignments]);
    }

    public function take(Request $request, int $id): JsonResponse
    {
        $assignment = ManagerAssignment::where('id', $id)
            ->where('manager_id', $request->user()->id)
            ->where('statut', 'ATTRIBUE')
            ->firstOrFail();

        $assignment->update([
            'statut' => 'PRIS_EN_CHARGE',
            'taken_at' => now(),
        ]);

        $this->updateDossierStatus($assignment->dossier_type, $assignment->dossier_id, 'OPENER');

        return response()->json(['message' => 'Dossier pris en charge', 'assignment' => $assignment]);
    }

    public function close(Request $request, int $id): JsonResponse
    {
        $assignment = ManagerAssignment::where('id', $id)
            ->where('manager_id', $request->user()->id)
            ->firstOrFail();

        $assignment->update([
            'statut' => 'CLOTURE',
            'closed_at' => now(),
        ]);

        $this->updateDossierStatus($assignment->dossier_type, $assignment->dossier_id, 'CLOSE');

        return response()->json(['message' => 'Dossier clôturé', 'assignment' => $assignment]);
    }

    protected function updateDossierStatus(string $type, int $dossierId, string $mode): void
    {
        $match = [
            'OBJET_PERDU' => LostItemReport::class,
            'LITIGE' => Dispute::class,
            'SOS' => SosAlert::class,
            'IDENTITE' => IdentityVerification::class,
        ];

        $model = $match[$type] ?? null;
        if (! $model) {
            return;
        }

        $dossier = $model::find($dossierId);
        if (! $dossier) {
            return;
        }

        $message = $mode === 'OPENER' ? 'EN_COURS' : 'CLOTURE';

        if ($dossier instanceof SosAlert && in_array($dossier->statut, ['DETECTE', 'VERIFICATION', 'DECLENCHE', 'NOTIFIE'])) {
            $dossier->update(['statut' => $message === 'CLOTURE' ? 'CLOTE' : 'EN_COURS']);
        } elseif ($dossier instanceof LostItemReport && $dossier->statut === 'SIGNALE') {
            $dossier->update(['statut' => $message === 'CLOTURE' ? 'CLOTURE' : 'EN_RECHERCHE']);
        } elseif ($dossier instanceof Dispute && $dossier->statut === 'OUVERT') {
            $dossier->update(['statut' => $message === 'CLOTURE' ? 'CLOTURE' : 'EN_COURS']);
        } elseif ($dossier instanceof IdentityVerification && $dossier->statut === 'EN_ATTENTE') {
            $dossier->update(['statut' => $message === 'CLOTURE' ? 'ECHOUE' : 'A_EXAMINER']);
        }
    }
}