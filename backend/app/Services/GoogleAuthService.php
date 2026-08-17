<?php

namespace App\Services;

use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/**
 * Vérifie les jetons d'identité (ID token) Google émis par l'application
 * mobile. La validation se fait côté Google (tokeninfo) et le champ `aud`
 * doit correspondre à un de nos OAuth client IDs.
 */
class GoogleAuthService
{
    public function verifyIdToken(string $idToken): ?array
    {
        try {
            $response = Http::timeout(10)->get('https://oauth2.googleapis.com/tokeninfo', [
                'id_token' => $idToken,
            ]);
        } catch (\Throwable $e) {
            Log::warning('Google tokeninfo call failed', ['error' => $e->getMessage()]);

            return null;
        }

        if (! $response->successful()) {
            Log::warning('Google tokeninfo rejected', ['status' => $response->status()]);

            return null;
        }

        $claims = $response->json();

        if (! is_array($claims) || empty($claims['email']) || empty($claims['sub'])) {
            return null;
        }

        // Le jeton doit avoir été émis pour notre application (aud audience).
        $allowed = array_values(array_filter([
            config('services.google.client_id'),
            config('services.google.android_client_id'),
        ]));

        if ($allowed !== [] && ! in_array($claims['aud'] ?? null, $allowed, true)) {
            Log::warning('Google token aud mismatch', ['aud' => $claims['aud'] ?? null]);

            return null;
        }

        return $claims;
    }
}