<?php

namespace App\Http\Controllers;

use App\Models\IdentityDocument;
use App\Models\IdentityVerification;
use App\Models\ManagerAssignment;
use App\Models\Notification;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class IdentityController extends Controller
{
    public function submit(Request $request): JsonResponse
    {
        $data = $request->validate([
            'type' => 'required|in:CNI,PASSEPORT,AUTRE',
            'numero' => 'nullable|string|max:100',
            'fichier_url' => 'required|string',
        ]);

        $verification = IdentityVerification::create([
            'user_id' => $request->user()->id,
            'type' => $data['type'],
            'statut' => 'EN_ATTENTE',
        ]);

        $document = IdentityDocument::create([
            'user_id' => $request->user()->id,
            'verification_id' => $verification->id,
            'type' => $data['type'],
            'numero' => $data['numero'] ?? null,
            'fichier_url' => $data['fichier_url'],
        ]);

        $this->assignIdentityReview($verification);

        return response()->json([
            'message' => 'Document soumis pour vérification',
            'verification' => $verification->load('document'),
        ], 201);
    }

    public function status(Request $request): JsonResponse
    {
        $verification = IdentityVerification::with('document')
            ->where('user_id', $request->user()->id)
            ->latest()
            ->first();

        return response()->json([
            'verification' => $verification,
            'identite_verifiee' => $verification?->statut === 'VERIFIE' ?? false,
        ]);
    }

    public function review(Request $request, int $id): JsonResponse
    {
        $data = $request->validate([
            'statut' => 'required|in:VERIFIE,ECHOUE,A_EXAMINER',
            'provider_kyc' => 'nullable|string|max:100',
        ]);

        $verification = IdentityVerification::findOrFail($id);

        $verification->update([
            'statut' => $data['statut'],
            'provider_kyc' => $data['provider_kyc'] ?? null,
            'verifie_le' => now(),
        ]);

        if ($data['statut'] === 'A_EXAMINER') {
            $this->assignIdentityReview($verification);
        }

        Notification::create([
            'user_id' => $verification->user_id,
            'type' => 'IDENTITE',
            'titre' => 'Statut de votre vérification d\'identité',
            'message' => 'Votre vérification est : ' . $data['statut'],
        ]);

        return response()->json([
            'message' => 'Vérification mise à jour',
            'verification' => $verification,
        ]);
    }

    public function pending(Request $request): JsonResponse
    {
        $verifications = IdentityVerification::with('user', 'document')
            ->where('statut', 'EN_ATTENTE')
            ->latest()
            ->get();

        return response()->json(['verifications' => $verifications]);
    }

    protected function assignIdentityReview(IdentityVerification $verification): void
    {
        if ($verification->statut === 'EN_ATTENTE') {
            $manager = $this->leastBusyManager();
            if ($manager) {
                ManagerAssignment::create([
                    'manager_id' => $manager->id,
                    'dossier_type' => 'IDENTITE',
                    'dossier_id' => $verification->id,
                    'statut' => 'ATTRIBUE',
                ]);
            }
        }
    }

    protected function leastBusyManager(): ?User
    {
        return User::whereHas('roles', fn ($q) => $q->where('slug', 'gestionnaire'))
            ->withCount(['managerAssignments as ouvertes' => fn ($q) => $q->where('statut', '!=', 'CLOTURE')])
            ->orderBy('ouvertes')
            ->first();
    }
}