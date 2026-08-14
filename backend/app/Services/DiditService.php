<?php

namespace App\Services;

use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/**
 * Intégration Didit (KYC) — API standalone « ID Verification ».
 * Vérifie un document d'identité (CNI / passeport) et renvoie une décision
 * réelle et synchronique (statut, nom, n° de document, warnings…).
 *
 * Doc : https://docs.didit.me  —  Auth : en-tête `x-api-key`.
 */
class DiditService
{
    protected string $baseUrl;

    protected ?string $apiKey;

    public function __construct()
    {
        $this->baseUrl = rtrim(config('services.didit.base_url', 'https://verification.didit.me/v3'), '/');
        $this->apiKey = config('services.didit.key');
    }

    public function isEnabled(): bool
    {
        return ! empty($this->apiKey);
    }

    /**
     * Vérifie un document d'identité via Didit.
     *
     * @param  string      $frontImageContents  octets de l'image recto
     * @param  string|null $backImageContents   octets de l'image verso (optionnel)
     */
    public function verifyIdDocument(string $frontImageContents, ?string $backImageContents = null): array
    {
        $request = Http::withHeaders(['x-api-key' => $this->apiKey])
            ->timeout(30)
            ->attach('front_image', $frontImageContents, 'front.jpg', ['Content-Type' => 'image/jpeg']);

        if ($backImageContents !== null) {
            $request->attach('back_image', $backImageContents, 'back.jpg', ['Content-Type' => 'image/jpeg']);
        }

        $response = $request->post($this->baseUrl.'/id-verification/');

        if (! $response->successful()) {
            Log::warning('Didit id-verification échec', [
                'status' => $response->status(),
                'body' => $response->body(),
            ]);

            return ['status' => 'error', 'http_status' => $response->status(), 'body' => $response->json() ?? $response->body()];
        }

        return $response->json();
    }

    /**
     * Vérifie que la clé API Didit est valide (endpoint healthcheck, sans
     * consommer de crédit de vérification).
     */
    public function healthcheck(): array
    {
        $response = Http::withHeaders(['x-api-key' => $this->apiKey])
            ->timeout(15)
            ->get($this->baseUrl.'/healthcheck/');

        return [
            'ok' => $response->successful(),
            'http_status' => $response->status(),
            'body' => $response->json() ?? $response->body(),
        ];
    }
}
