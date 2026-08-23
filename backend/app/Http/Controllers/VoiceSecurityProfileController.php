<?php

namespace App\Http\Controllers;

use App\Models\VoiceSecurityProfile;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class VoiceSecurityProfileController extends Controller
{
    /**
     * Définit le mot de sécurité du passager (utilisé pour le déclenchement SOS vocal).
     */
    public function setSecurityWord(Request $request): JsonResponse
    {
        $data = $request->validate([
            'mot_securite' => 'required|string|min:3|max:40',
        ]);

        $profile = VoiceSecurityProfile::updateOrCreate(
            ['user_id' => $request->user()->id],
            ['mot_securite' => $data['mot_securite']],
        );

        return response()->json([
            'message' => 'Mot de sécurité enregistré',
            'profile' => $this->publicProfile($profile),
        ]);
    }

    /**
     * Enrôle l'empreinte vocale : embedding de voix (ECAPA-TDNN, calculé sur le mobile)
     * envoyé comme tableau de nombres. Stocké en JSON, comparé par similarité cosinus.
     */
    public function enroll(Request $request): JsonResponse
    {
        $data = $request->validate([
            'empreinte' => 'required',
        ]);

        $empreinte = $data['empreinte'];
        // Validation stricte P1-4 : 192 floats pour ECAPA, ou 64 hex pour token repli
        if (is_array($empreinte)) {
            if (count($empreinte) !== 192) {
                return response()->json(['message' => 'Empreinte vocale invalide : 192 valeurs attendues, '.count($empreinte).' reçues'], 422);
            }
            $request->validate(['empreinte.*' => 'numeric']);
            $stored = json_encode(array_values($empreinte));
        } else {
            if (!is_string($empreinte) || !preg_match('/^[a-f0-9]{64}$/i', (string) $empreinte)) {
                return response()->json(['message' => 'Empreinte token invalide : sha256 64 hex attendu'], 422);
            }
            $stored = json_encode($empreinte);
        }

        $profile = VoiceSecurityProfile::updateOrCreate(
            ['user_id' => $request->user()->id],
            ['empreinte_vocale' => $stored, 'actif' => true],
        );

        return response()->json([
            'message' => 'Empreinte vocale enrôlée',
            'profile' => $this->publicProfile($profile),
        ]);
    }

    public function show(Request $request): JsonResponse
    {
        $profile = VoiceSecurityProfile::where('user_id', $request->user()->id)->first();

        return response()->json([
            'profile' => $profile ? $this->publicProfile($profile) : null,
        ]);
    }

    protected function publicProfile(VoiceSecurityProfile $profile): array
    {
        return [
            'mot_securite' => $profile->mot_securite,
            'actif' => $profile->actif,
            'enrolled' => $profile->empreinte_vocale !== null,
        ];
    }
}
