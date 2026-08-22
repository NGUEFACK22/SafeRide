<?php

namespace App\Services;

use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/**
 * Envoi WhatsApp via Infobip (SOS aux contacts d'urgence).
 * - SMS reste le canal obligatoire (toujours envoyé)
 * - WhatsApp est un complément : on vérifie d'abord si le numéro est sur WhatsApp,
 *   puis on tente l'envoi. Si le numéro n'est pas sur WhatsApp, on reste en SMS seul.
 *
 * Endpoint Infobip WhatsApp : POST /whatsapp/1/message/text
 * Auth : App {api_key}  (même clé que SMS)
 * Vérif contact : POST /whatsapp/1/contacts  (optionnel, fallback optimiste)
 */
class WhatsappService
{
    protected ?string $apiKey;
    protected ?string $baseUrl;
    protected ?string $sender; // ex: 447860099299 (numéro WhatsApp Business validé Infobip)

    public function __construct()
    {
        $this->apiKey = config('services.infobip.api_key');
        $this->baseUrl = rtrim(config('services.infobip.base_url', 'https://api.infobip.com'), '/');
        // Sender WhatsApp dédié (si vide, on réutilise le sender SMS mais l'envoi échouera proprement)
        $this->sender = config('services.whatsapp.sender') ?? config('services.infobip.sender');
    }

    public function ready(): bool
    {
        return !empty($this->apiKey) && !empty($this->sender);
    }

    /**
     * Vérifie si le numéro est joignable sur WhatsApp.
     * Retourne true si on peut tenter l'envoi, false sinon.
     * En l'absence de l'API contacts (ou sender non WhatsApp), on est optimiste et on tente quand même.
     */
    public function isOnWhatsApp(string $to): bool
    {
        if (!$this->ready() || trim($to) === '') {
            return false;
        }

        // Format E.164 requis pour WhatsApp
        $to = $this->normalize($to);
        if ($to === null) {
            return false;
        }

        try {
            // Tentative de vérification via Infobip si endpoint dispo
            $response = Http::withHeaders([
                'Authorization' => 'App ' . $this->apiKey,
                'Content-Type' => 'application/json',
                'Accept' => 'application/json',
            ])->timeout(8)->post($this->baseUrl . '/whatsapp/1/contacts', [
                'contacts' => [$to],
            ]);

            if ($response->successful()) {
                $contacts = $response->json('contacts') ?? [];
                if (!empty($contacts) && is_array($contacts)) {
                    $status = strtolower($contacts[0]['status'] ?? '');
                    // Infobip renvoie status "valid" / "invalid"
                    if ($status === 'invalid' || $status === 'not_registered') {
                        return false;
                    }
                    if ($status === 'valid' || $status === 'registered') {
                        return true;
                    }
                }
                // Réponse inattendue -> on tente l'envoi (optimiste)
                return true;
            }

            // 400/404 sur /contacts = sender non WhatsApp ou non autorisé -> fallback optimiste
            if (in_array($response->status(), [400, 401, 403, 404])) {
                Log::info('WhatsApp contacts check non dispo, mode optimiste', ['status' => $response->status()]);
                return true;
            }

            return true;
        } catch (\Throwable $e) {
            Log::warning('WhatsApp isOnWhatsApp check failed, mode optimiste', ['to' => $to, 'error' => $e->getMessage()]);
            return true; // on tente l'envoi, qui échouera proprement si pas sur WhatsApp
        }
    }

    /**
     * Envoie un message WhatsApp texte. Retourne true si accepté.
     */
    public function send(string $to, string $message): bool
    {
        if (!$this->ready() || trim($to) === '' || trim($message) === '') {
            return false;
        }

        $to = $this->normalize($to);
        if ($to === null) {
            return false;
        }

        try {
            $payload = [
                'from' => $this->sender,
                'to' => $to,
                'messageId' => 'saferide-' . uniqid(),
                'content' => [
                    'text' => $message,
                ],
            ];

            $response = Http::withHeaders([
                'Authorization' => 'App ' . $this->apiKey,
                'Content-Type' => 'application/json',
                'Accept' => 'application/json',
            ])->timeout(10)->post($this->baseUrl . '/whatsapp/1/message/text', $payload);

            if ($response->successful()) {
                $body = $response->json();
                // Infobip renvoie messages[0].status.name = PENDING / ACCEPTED
                $msg = $body['messages'][0] ?? $body;
                $name = $msg['status']['name'] ?? $msg['statusName'] ?? '';
                if (in_array($name, ['PENDING', 'PENDING_ACCEPTED', 'ACCEPTED', 'SENT'])) {
                    return true;
                }
                // Sans status explicite mais 2xx = considéré comme accepté
                return true;
            }

            // Cas "recipient not on WhatsApp" -> Infobip renvoie 400 avec description
            $body = $response->json();
            $desc = strtolower(json_encode($body));
            if (str_contains($desc, 'not on whatsapp') || str_contains($desc, 'not_registered') || str_contains($desc, 'invalid recipient')) {
                Log::info('WhatsApp recipient not on WhatsApp', ['to' => $to]);
                return false;
            }

            Log::warning('WhatsApp send non-success', ['to' => $to, 'status' => $response->status(), 'body' => $response->body()]);
            return false;
        } catch (\Throwable $e) {
            Log::warning('WhatsApp send failed', ['to' => $to, 'error' => $e->getMessage()]);
            return false;
        }
    }

    /**
     * Normalise en E.164 (+237...). Retourne null si format invalide.
     */
    protected function normalize(string $to): ?string
    {
        $to = trim($to);
        // Supprime espaces / tirets
        $to = preg_replace('/[\s\-\(\)]/', '', $to);
        if ($to === null || $to === '') return null;
        if (!str_starts_with($to, '+')) {
            // Sans +, on préfixe +237 si 9 chiffres (CM) sinon refuse
            if (preg_match('/^6\d{8}$/', $to)) {
                $to = '+237' . $to;
            } else {
                return null;
            }
        }
        if (!preg_match('/^\+\d{8,15}$/', $to)) {
            return null;
        }
        return $to;
    }
}
