<?php

namespace App\Services;

use App\Models\FcmToken;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

class FcmService
{
    protected array $account = [];

    public function __construct()
    {
        $path = config('fcm.credentials_path');
        if (is_file($path)) {
            $decoded = json_decode((string) file_get_contents($path), true);
            if (is_array($decoded)
                && isset($decoded['client_email'], $decoded['private_key'], $decoded['project_id'])) {
                $this->account = $decoded;
            }
        }
    }

    protected function ready(): bool
    {
        return $this->account !== [];
    }

    protected function accessToken(): ?string
    {
        if (! $this->ready()) {
            return null;
        }

        $now = time();
        $header = $this->b64url(json_encode([
            'alg' => 'RS256',
            'typ' => 'JWT',
            'kid' => $this->account['private_key_id'],
        ]));
        $claims = $this->b64url(json_encode([
            'iss' => $this->account['client_email'],
            'scope' => 'https://www.googleapis.com/auth/firebase.messaging',
            'aud' => $this->account['token_uri'] ?? 'https://oauth2.googleapis.com/token',
            'iat' => $now,
            'exp' => $now + 3600,
        ]));

        $privateKey = str_replace('\\n', "\n", $this->account['private_key']);
        $signature = '';
        openssl_sign($header.'.'.$claims, $signature, $privateKey, 'sha256WithRSAEncryption');

        $assertion = $header.'.'.$claims.'.'.$this->b64url($signature);

        $response = Http::asForm()->post(
            $this->account['token_uri'] ?? 'https://oauth2.googleapis.com/token',
            [
                'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
                'assertion' => $assertion,
            ]
        );

        if (! $response->successful()) {
            Log::warning('FCM token exchange failed', ['status' => $response->status()]);

            return null;
        }

        return $response->json('access_token');
    }

    public function sendToUser(int $userId, string $title, string $body, array $data = []): void
    {
        $tokens = FcmToken::where('user_id', $userId)->pluck('token')->all();
        $this->sendToTokens($tokens, $title, $body, $data);
    }

    public function sendToTokens(array $tokens, string $title, string $body, array $data = []): void
    {
        if (! $this->ready() || $tokens === []) {
            return;
        }

        $accessToken = $this->accessToken();
        if ($accessToken === null) {
            return;
        }

        foreach (array_unique($tokens) as $token) {
            try {
                Http::withToken($accessToken)->post(
                    sprintf('https://fcm.googleapis.com/v1/projects/%s/messages:send', $this->account['project_id']),
                    [
                        'message' => [
                            'token' => $token,
                            'notification' => [
                                'title' => $title,
                                'body' => $body,
                            ],
                            'data' => array_map('strval', $data),
                        ],
                    ]
                );
            } catch (\Throwable $e) {
                Log::warning('FCM send failed', ['error' => $e->getMessage()]);
            }
        }
    }

    protected function b64url(string $value): string
    {
        return rtrim(strtr(base64_encode($value), '+/', '-_'), '=');
    }
}