<?php

namespace App\Http\Controllers;

use App\Models\Vehicle;
use App\Models\QrCode;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Str;

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
        $data = $request->validate([
            'marque' => 'required|string|max:60',
            'modele' => 'required|string|max:60',
            'immatriculation' => 'required|string|max:20|unique:vehicles',
            'type' => 'required|in:MOTO,VOITURE,MINIBUS,BUS',
            'couleur' => 'nullable|string|max:30',
        ]);

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
        ]));

        return response()->json([
            'message' => 'Véhicule ajouté avec son QR associé',
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
        $vehicle->delete();

        return response()->json(['message' => 'Véhicule supprimé']);
    }

    public function qr(Request $request, int $id): JsonResponse
    {
        $vehicle = Vehicle::where('id', $id)->where('transporteur_id', $request->user()->id)->firstOrFail();
        $qr = $vehicle->qrCodes()->latest()->first();

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
        $qr = $vehicle->qrCodes()->latest()->firstOrFail();

        $qr->update(['actif' => ! $qr->actif]);

        return response()->json([
            'message' => 'QR ' . ($qr->actif ? 'activé' : 'désactivé'),
            'qr' => $qr,
        ]);
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

    protected function generateSignedToken(Vehicle $vehicle): string
    {
        $payload = json_encode([
            'vid' => $vehicle->id,
            'immatriculation' => $vehicle->immatriculation,
            'n' => Str::random(12),
            'exp' => now()->addMonths(3)->timestamp,
        ]);

        $signature = hash_hmac('sha256', $payload, config('app.key'));

        return base64_encode($payload . '.' . $signature);
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
            'expires_at' => isset($payload['exp']) ? date('c', $payload['exp']) : null,
        ];
    }
}