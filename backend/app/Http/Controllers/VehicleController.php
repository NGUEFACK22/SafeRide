<?php

namespace App\Http\Controllers;

use App\Models\Vehicle;
use App\Models\QrCode;
use App\Services\QrTokenService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class VehicleController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $vehicles = Vehicle::with('qrCodes')
            ->where('transporteur_id', $request->user()->id)
            ->get();

        return response()->json(['vehicles' => $vehicles]);
    }

    public function store(Request $request): JsonResponse
    {
        // Compte transporteur vérifié (KYC) exigé pour créer un véhicule/QR.
        if (! $request->user()->isIdentiteVerifiee()) {
            return response()->json(['message' => 'Compte non vérifié — vérifiez votre identité pour ajouter un véhicule.'], 403);
        }

        $data = $request->validate([
            'marque' => 'required|string|max:60',
            'modele' => 'required|string|max:60',
            'immatriculation' => 'required|string|max:20|unique:vehicles',
            'type' => 'required|in:MOTO,VOITURE,MINIBUS,BUS',
            'couleur' => 'nullable|string|max:30',
        ]);

        // Règle métier : un transporteur ne peut avoir qu'un seul véhicule
        // Si déjà un véhicule existe, on le remplace (supprime l'ancien et ses QR)
        $existingVehicles = Vehicle::where('transporteur_id', $request->user()->id)->get();
        if ($existingVehicles->count() >= 1) {
            // Supprimer les anciens QR puis les véhicules (nettoyage si doublons)
            foreach ($existingVehicles as $old) {
                $old->qrCodes()->delete();
                $old->delete();
            }
        }

        $vehicle = Vehicle::create([
            'transporteur_id' => $request->user()->id,
            'marque' => $data['marque'],
            'modele' => $data['modele'],
            'immatriculation' => $data['immatriculation'],
            'type' => $data['type'],
            'couleur' => $data['couleur'] ?? null,
            'statut' => 'ACTIF',
        ]);

        $vehicle->qrCodes()->save(new QrCode([
            'token' => $this->generateSignedToken($vehicle),
            'actif' => true,
            'expires_at' => now()->addHours(QrTokenService::ttlHours()),
        ]));

        return response()->json([
            'message' => $existingVehicles->count() >= 1 ? 'Véhicule remplacé (un seul véhicule autorisé) avec son QR associé' : 'Véhicule ajouté avec son QR associé',
            'vehicle' => $vehicle->load('qrCodes'),
        ], 201);
    }

    public function update(Request $request, int $id): JsonResponse
    {
        $vehicle = Vehicle::where('id', $id)->where('transporteur_id', $request->user()->id)->firstOrFail();

        $data = $request->validate([
            'marque' => 'sometimes|string|max:60',
            'modele' => 'sometimes|string|max:60',
            'immatriculation' => 'sometimes|string|max:20|unique:vehicles,immatriculation,' . $id,
            'type' => 'sometimes|in:MOTO,VOITURE,MINIBUS,BUS',
            'couleur' => 'sometimes|nullable|string|max:30',
            'statut' => 'sometimes|in:ACTIF,INACTIF',
        ]);

        $vehicle->update($data);

        return response()->json([
            'message' => 'Véhicule mis à jour',
            'vehicle' => $vehicle->load('qrCodes'),
        ]);
    }

    public function destroy(Request $request, int $id): JsonResponse
    {
        $vehicle = Vehicle::where('id', $id)->where('transporteur_id', $request->user()->id)->firstOrFail();

        // Empêcher la suppression du dernier véhicule si c'est le seul
        $count = Vehicle::where('transporteur_id', $request->user()->id)->count();
        if ($count <= 1) {
            return response()->json([
                'message' => 'Impossible de supprimer votre seul véhicule. Un transporteur doit conserver au moins un véhicule. Ajoutez d\'abord un nouveau véhicule (il remplacera l\'ancien).'
            ], 422);
        }

        $vehicle->qrCodes()->delete();
        $vehicle->delete();

        // Nettoyage : si doublons existent (plus d'1 véhicule), ne garder que le plus récent
        $remaining = Vehicle::where('transporteur_id', $request->user()->id)->orderBy('created_at', 'desc')->get();
        if ($remaining->count() > 1) {
            foreach ($remaining->skip(1) as $extra) {
                $extra->qrCodes()->delete();
                $extra->delete();
            }
        }

        return response()->json(['message' => 'Véhicule supprimé']);
    }

    public function qr(Request $request, int $id): JsonResponse
    {
        $vehicle = Vehicle::where('id', $id)->where('transporteur_id', $request->user()->id)->firstOrFail();

        // Rotation auto (24h) : garantit un QR actif et renvoie l'état réel.
        $qr = $this->ensureFreshQr($vehicle);

        return response()->json([
            'qr' => $qr ? [
                'token' => $qr->token,
                'actif' => $qr->actif,
                'expires_at' => $qr->expires_at,
                'contenu' => $qr->actif ? $this->qrPayload($qr) : null,
            ] : null,
        ]);
    }

    public function toggleQr(Request $request, int $id): JsonResponse
    {
        $vehicle = Vehicle::where('id', $id)->where('transporteur_id', $request->user()->id)->firstOrFail();
        $qr = $vehicle->qrCodes()->orderByDesc('id')->firstOrFail();

        $qr->update(['actif' => ! $qr->actif]);

        return response()->json([
            'message' => 'QR ' . ($qr->actif ? 'activé' : 'désactivé'),
            'qr' => $qr,
        ]);
    }

    /**
     * Régénère MANUELLEMENT le QR code du véhicule (nouveau token immédiatement
     * actif, validité 24h). Les anciens QR (imprimés ou encore affichés) sont
     * désactivés : ils ne pourront plus lancer de trajet.
     */
    public function refreshQr(Request $request, int $id): JsonResponse
    {
        $vehicle = Vehicle::where('id', $id)->where('transporteur_id', $request->user()->id)->firstOrFail();

        $qr = $this->rotateForNewRide($vehicle);

        return response()->json([
            'message' => 'QR Code régénéré',
            'qr' => [
                'token' => $qr->token,
                'actif' => $qr->actif,
                'expires_at' => $qr->expires_at,
                'contenu' => $this->qrPayload($qr),
            ],
        ]);
    }

    /**
     * Rotation du QR (désactive les actifs, crée un actif 24h).
     * Utilisée par :
     * - refreshQr (manuelle, à la demande du transporteur) ;
     * - TripController::confirmDestination (auto, quand le trajet démarre
     *   réellement : le QR scanné meurt, un QR frais attend les prochains
     *   passagers — le transporteur le voit via son poll /qr).
     */
    public function rotateForNewRide(Vehicle $vehicle): QrCode
    {
        // Désactiver tous les anciens QR du véhicule, puis créer le nouveau.
        $vehicle->qrCodes()->where('actif', true)->update(['actif' => false]);

        return $vehicle->qrCodes()->create([
            'token' => $this->generateSignedToken($vehicle),
            'actif' => true,
            'expires_at' => now()->addHours(QrTokenService::ttlHours()),
        ]);
    }

    /**
     * Garantit un QR ACTIF pour le véhicule :
     * - tant que le QR actuel a moins de QR_VALIDITY_HOURS (24h par défaut), il
     *   est réutilisé (multi-usage) et réactivé s'il avait été désactivé ;
     * - dès que 24h sont écoulées, un nouveau QR est généré automatiquement
     *   et les précédents sont désactivés (rotation auto).
     */
    public function ensureFreshQr(Vehicle $vehicle): ?QrCode
    {
        $ttl = QrTokenService::ttlHours();
        $now = now();
        $qr = $vehicle->qrCodes()->orderByDesc('id')->first();

        if ($qr !== null && $qr->created_at !== null && $qr->created_at->gte($now->copy()->subHours($ttl))) {
            // QR encore dans la fenêtre de validité : réutilisable tel quel.
            if (! $qr->actif) {
                $qr->update([
                    'actif' => true,
                    'expires_at' => $qr->created_at->addHours($ttl),
                ]);
            }

            return $qr;
        }

        // Rotation auto : QR périmé (>24h) → nouveau QR actif, anciens inactifs.
        $new = $vehicle->qrCodes()->create([
            'token' => $this->generateSignedToken($vehicle),
            'actif' => true,
            'expires_at' => $now->addHours($ttl),
        ]);
        $vehicle->qrCodes()
            ->where('id', '!=', $new->id)
            ->where('actif', true)
            ->update(['actif' => false]);

        return $new;
    }

    /**
     * Rotation auto de TOUS les QR périmés (appelée par la tâche planifiée qr:rotate).
     */
    public function rotateAllExpired(): int
    {
        $rotated = 0;
        Vehicle::chunk(100, function ($vehicles) use (&$rotated) {
            foreach ($vehicles as $vehicle) {
                $this->ensureFreshQr($vehicle);
                $rotated++;
            }
        });

        return $rotated;
    }

    /**
     * Met à jour la position GPS du véhicule (transporteur).
     * Permet la vérification de proximité lors du scan du QR par le passager.
     */
    public function position(Request $request, int $id): JsonResponse
    {
        $vehicle = Vehicle::where('id', $id)->where('transporteur_id', $request->user()->id)->firstOrFail();

        $data = $request->validate([
            'latitude' => 'required|numeric|between:-90,90',
            'longitude' => 'required|numeric|between:-180,180',
        ]);

        $vehicle->update([
            'last_latitude' => $data['latitude'],
            'last_longitude' => $data['longitude'],
            'last_position_at' => now(),
        ]);

        return response()->json([
            'message' => 'Position du véhicule mise à jour',
            'vehicle' => $vehicle->only('id', 'last_latitude', 'last_longitude', 'last_position_at'),
        ]);
    }

    /**
     * Génère un token QR signé cohérent (accessible aux autres contrôleurs).
     */
    public function signedTokenFor(Vehicle $vehicle): string
    {
        return app(QrTokenService::class)->generate($vehicle);
    }

    protected function generateSignedToken(Vehicle $vehicle): string
    {
        return app(QrTokenService::class)->generate($vehicle);
    }

    protected function qrPayload(QrCode $qr): array
    {
        $parts = explode('.', base64_decode($qr->token), 2);
        if (count($parts) !== 2) {
            return [];
        }

        $payload = json_decode($parts[0], true);

        return [
            'vehicle_id' => $payload['vid'] ?? null,
            'immatriculation' => $payload['immatriculation'] ?? null,
            'transporteur_id' => $payload['transporteur_id'] ?? null,
            'transporteur_nom' => $payload['transporteur_nom'] ?? null,
            'transporteur_prenom' => $payload['transporteur_prenom'] ?? null,
            'transporteur_fullname' => $payload['transporteur_fullname'] ?? trim(($payload['transporteur_prenom'] ?? '') . ' ' . ($payload['transporteur_nom'] ?? '')),
            'expires_at' => isset($payload['exp']) ? date('c', $payload['exp']) : null,
        ];
    }
}