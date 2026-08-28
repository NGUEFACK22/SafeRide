<?php

namespace App\Http\Controllers;

use App\Models\IdentityDocument;
use App\Models\IdentityVerification;
use App\Models\ManagerAssignment;
use App\Models\Notification;
use App\Models\User;
use App\Services\DiditService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Http;

class IdentityController extends Controller
{
    public function __construct(private DiditService $didit)
    {
    }

    public function submit(Request $request): JsonResponse
    {
        $data = $request->validate([
            'type' => 'required|in:CNI,PASSEPORT',
            'numero' => 'nullable|string|max:100',
            // Nouveau flux : selfie avec pièce en main + recto + verso obligatoires (ou ancien fichier unique/url pour tests)
            'fichier_recto' => 'required_without_all:fichier,fichier_url|file|image|mimes:jpeg,jpg,png|mimetypes:image/jpeg,image/png|max:10240',
            'fichier_verso' => 'required_without_all:fichier,fichier_url|file|image|mimes:jpeg,jpg,png|mimetypes:image/jpeg,image/png|max:10240',
            'fichier_selfie' => 'required_without_all:fichier,fichier_url|file|image|mimes:jpeg,jpg,png|mimetypes:image/jpeg,image/png|max:10240',
            'fichier' => 'nullable|file|image|mimes:jpeg,jpg,png|mimetypes:image/jpeg,image/png|max:10240',
            'fichier_url' => 'nullable|string',
        ]);

        // Nouveau flux : 3 fichiers obligatoires, sinon fallback ancien flux (tests)
        if ($request->hasFile('fichier_recto') && $request->hasFile('fichier_verso') && $request->hasFile('fichier_selfie')) {
            $rectoPath = $request->file('fichier_recto')->store('identity', 'public');
            $versoPath = $request->file('fichier_verso')->store('identity', 'public');
            $selfiePath = $request->file('fichier_selfie')->store('identity', 'public');

            $verification = IdentityVerification::create([
                'user_id' => $request->user()->id,
                'type' => $data['type'],
                'statut' => 'EN_ATTENTE',
                'recto_url' => $rectoPath,
                'verso_url' => $versoPath,
                'selfie_url' => $selfiePath,
            ]);

            $base = ['user_id' => $request->user()->id, 'verification_id' => $verification->id, 'type' => $data['type'], 'numero' => $data['numero'] ?? null];
            $docRecto = IdentityDocument::create(array_merge($base, ['fichier_url' => $rectoPath]));
            $docVerso = IdentityDocument::create(array_merge($base, ['fichier_url' => $versoPath]));
            $docSelfie = IdentityDocument::create(array_merge($base, ['fichier_url' => $selfiePath]));

            $finalStatut = 'EN_ATTENTE';

            if ($this->didit->isEnabled()) {
                try {
                    $rectoContents = file_get_contents($request->file('fichier_recto')->getRealPath());
                    $versoContents = file_get_contents($request->file('fichier_verso')->getRealPath());
                    $result = $this->didit->verifyIdDocument($rectoContents, $versoContents);
                    $docRecto->update(['ocr_data' => $result]);
                    $finalStatut = $this->determineKycStatus($result);
                    $verification->update(['provider_kyc' => 'didit', 'statut' => $finalStatut, 'verifie_le' => now()]);
                    $extracted = $result['id_verification']['form_values']['document_number'] ?? $result['id_verification']['extracted_data']['document_number'] ?? null;
                    if ($extracted) $verification->update(['recto_url' => $rectoPath]);
                } catch (\Throwable $e) {
                    $finalStatut = 'EN_ATTENTE';
                    \Log::warning('Didit KYC échec', ['error' => $e->getMessage()]);
                }
            }

            if (in_array($finalStatut, ['EN_ATTENTE', 'A_EXAMINER', 'VERIFIE'], true) && $selfiePath) {
                if ($finalStatut === 'VERIFIE') {
                    $finalStatut = 'A_EXAMINER';
                    $verification->update(['statut' => 'A_EXAMINER']);
                }
                $this->assignIdentityReview($verification);
            } elseif (in_array($finalStatut, ['EN_ATTENTE', 'A_EXAMINER'], true)) {
                $this->assignIdentityReview($verification);
            }

            $msg = match (true) {
                $finalStatut === 'VERIFIE' => 'Identité vérifiée automatiquement via Didit',
                !$this->didit->isEnabled() => 'Documents soumis (recto, verso, selfie) — La vérification Didit nécessite une clé API. Votre dossier sera revu manuellement par un gestionnaire sous 24h.',
                $finalStatut === 'EN_ATTENTE' => 'Documents soumis — La vérification Didit nécessite des crédits. Votre dossier est en attente de revue manuelle par un gestionnaire.',
                default => 'Documents soumis (recto, verso, selfie) — vérification en cours (Didit + selfie à valider)',
            };
            return response()->json([
                'message' => $msg,
                'verification' => $verification->load('document'),
            ], 201);
        }

        // Fallback ancien flux (single fichier) pour compat tests
        if (! $request->filled('fichier_url') && ! $request->hasFile('fichier')) {
            return response()->json(['message' => 'Un document (fichier_url ou fichier) est requis.'], 422);
        }
        $verification = IdentityVerification::create(['user_id' => $request->user()->id, 'type' => $data['type'], 'statut' => 'EN_ATTENTE']);
        $docUrl = $request->input('fichier_url');
        if ($request->hasFile('fichier')) $docUrl = $request->file('fichier')->getClientOriginalName();
        $document = IdentityDocument::create(['user_id' => $request->user()->id, 'verification_id' => $verification->id, 'type' => $data['type'], 'numero' => $data['numero'] ?? null, 'fichier_url' => $docUrl]);
        $finalStatut = 'EN_ATTENTE';
        $image = $this->resolveImageContents($request);
        if ($image && $this->didit->isEnabled()) {
            try {
                $result = $this->didit->verifyIdDocument($image);
                $document->update(['ocr_data' => $result]);
                $finalStatut = $this->determineKycStatus($result);
                $verification->update(['provider_kyc' => 'didit', 'statut' => $finalStatut, 'verifie_le' => now()]);
                $extracted = $result['id_verification']['form_values']['document_number'] ?? $result['id_verification']['extracted_data']['document_number'] ?? null;
                if ($extracted && ! $verification->numero) { $verification->numero = $extracted; $verification->save(); }
            } catch (\Throwable $e) { $finalStatut = 'EN_ATTENTE'; \Log::warning('Didit KYC échec', ['error' => $e->getMessage()]); }
        }
        if (in_array($finalStatut, ['EN_ATTENTE', 'A_EXAMINER'], true)) $this->assignIdentityReview($verification);
        return response()->json(['message' => $finalStatut === 'VERIFIE' ? 'Identité vérifiée automatiquement via Didit' : 'Document soumis à vérification'.($this->didit->isEnabled() ? ' (Didit)' : ''), 'verification' => $verification->load('document')], 201);
    }

    /**
     * Résout le contenu binaire de l'image du document à partir d'un upload
     * ou d'une URL/chemin fourni.
     */
    protected function resolveImageContents(Request $request): ?string
    {
        if ($request->hasFile('fichier') && $request->file('fichier')->isValid()) {
            return file_get_contents($request->file('fichier')->getRealPath());
        }

        $url = $request->input('fichier_url');
        if (! $url) {
            return null;
        }

        if (filter_var($url, FILTER_VALIDATE_URL)) {
            $resp = Http::timeout(15)->get($url);

            return $resp->successful() ? $resp->body() : null;
        }

        foreach ([storage_path('app/'.$url), storage_path('app/public/'.$url), public_path($url), $url] as $candidate) {
            if (is_file($candidate)) {
                return file_get_contents($candidate);
            }
        }

        return null;
    }

    /**
     * Détermine le statut de vérification KYC suite à l'appel Didit.
     *
     * Standing normale :
     *   - Didit crédités + document approved → VERIFIE (auto)
     *   - Didit crédités + document declined → ECHOUE (auto)
     *   - Didit sans crédits / clé absente → EN_ATTENTE (revue manuelle)
     *   - Didit réponse inattendue / erreur → A_EXAMINER (revue manuelle)
     *
     * @param array $result Réponse complète de l'API Didit
     * @return string      L'un des statuts: VERIFIE, ECHOUE, EN_ATTENTE, A_EXAMINER
     */
    protected function determineKycStatus(array $result): string
    {
        // 1. Erreur HTTP ou réponse KO de Didit
        if (($result['status'] ?? '') === 'error') {
            return 'A_EXAMINER';
        }

        // 2. Réponse réussie Didit → vérifier le sous-ressultat
        $diditStatus = strtolower($result['id_verification']['status'] ?? 'unknown');

        return match ($diditStatus) {
            'approved' => 'VERIFIE',
            'declined' => 'ECHOUE',
            // Tout statut inattendu (pending, risk, etc.) → examen manuel
            default => 'A_EXAMINER',
        };
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
            ->paginate(20);

        return response()->json(['verifications' => $verifications]);
    }

    protected function assignIdentityReview(IdentityVerification $verification): void
    {
        if (in_array($verification->statut, ['EN_ATTENTE', 'A_EXAMINER'], true)) {
            $manager = $this->leastBusyManager();
            if ($manager) {
                ManagerAssignment::create([
                    'manager_id' => $manager->id,
                    'dossier_type' => 'IDENTITE',
                    'dossier_id' => $verification->id,
                    'statut' => 'ATTRIBUE',
                ]);

                Notification::create([
                    'user_id' => $manager->id,
                    'type' => 'IDENTITE',
                    'titre' => 'Nouvelle vérification d\'identité',
                    'message' => 'Identité de l\'utilisateur #' . $verification->user_id . ' à vérifier.',
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