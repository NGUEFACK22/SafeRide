<?php

namespace App\Services;

use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/**
 * Envoi de SMS via Infobip (notifications SOS aux contacts d'urgence).
 * Si les clés ne sont pas configurées, l'envoi est silencieusement ignoré.
 *
 * Endpoint : POST /sms/2/text/advanced
 * Auth     : Authorization: App {api_key}
 */
class SmsService
{
    protected ?string $apiKey = null;

    protected ?string $baseUrl = null;

    protected string $sender = 'SafeRide';

    public function __construct()
    {
        $this->apiKey = config('services.infobip.api_key');
        $this->baseUrl = config('services.infobip.base_url', 'https://api.infobip.com');
        $this->sender = config('services.infobip.sender', 'SafeRide');
    }

    public function ready(): bool
    {
        return $this->apiKey !== null && $this->apiKey !== '';
    }

    /**
     * Envoie un SMS. Renvoie true si le message a été accepté par l'API.
     * Le numéro doit être au format international (ex. +237690000000).
     */
    public function send(string $to, string $message): bool
    {
        if (! $this->ready() || trim($to) === '') {
            return false;
        }

        try {
            $response = Http::withHeaders([
                'Authorization' => 'App ' . $this->apiKey,
                'Content-Type' => 'application/json',
                'Accept' => 'application/json',
            ])->post($this->baseUrl . '/sms/2/text/advanced', [
                'messages' => [
                    [
                        'from' => $this->sender,
                        'destinations' => [
                            ['to' => $to],
                        ],
                        'text' => $message,
                    ],
                ],
            ]);

            if ($response->successful()) {
                $body = $response->json();
                // Vérifier le statut dans la réponse
                $messages = $body['messages'] ?? [];
                foreach ($messages as $msg) {
                    $name = $msg['status']['name'] ?? '';
                    if (in_array($name, ['PENDING_ACCEPTED', 'ACCEPTED'])) {
                        return true;
                    }
                }
            }

            return false;
        } catch (\Throwable $e) {
            Log::warning('Infobip SMS send failed', [
                'to' => $to,
                'error' => $e->getMessage(),
            ]);

            return false;
        }
    }
}
