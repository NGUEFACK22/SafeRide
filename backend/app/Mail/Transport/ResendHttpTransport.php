<?php

namespace App\Mail\Transport;

use Exception;
use GuzzleHttp\Client;
use Symfony\Component\Mailer\Envelope;
use Symfony\Component\Mailer\SentMessage;
use Symfony\Component\Mailer\Transport\AbstractTransport;
use Symfony\Component\Mime\Address;
use Symfony\Component\Mime\Email;
use Symfony\Component\Mime\MessageConverter;

/**
 * Transport Resend sans dépendance : appelle directement l'API HTTP
 * https://api.resend.com/emails (équivalent du ResendTransport de Laravel,
 * qui exige resend/resend-php — indisponible car Packagist bloque ici).
 *
 * Utilise Guzzle brut plutôt que la facade Http : le dispatcher curl de la
 * facade timeout sur la résolution DNS Windows/PHP locale, le handler
 * par défaut de Guzzle résout via le système de façon fiable.
 *
 * Enregistré comme mailer "resend-http" dans config/mail.php :
 * MAIL_MAILER=resend-http + RESEND_API_KEY.
 */
class ResendHttpTransport extends AbstractTransport
{
    public function __construct(
        protected string $apiKey,
        protected string $baseUrl = 'https://api.resend.com',
    ) {
        parent::__construct();
    }

    protected function doSend(SentMessage $message): void
    {
        $email = MessageConverter::toEmail($message->getOriginalMessage());
        $envelope = $message->getEnvelope();

        $payload = [
            'from' => $envelope->getSender()->toString(),
            'to' => $this->stringify($this->recipients($email, $envelope)),
            'subject' => $email->getSubject(),
            'html' => $email->getHtmlBody(),
            'text' => $email->getTextBody(),
        ];

        if ($email->getCc()) {
            $payload['cc'] = $this->stringify($email->getCc());
        }
        if ($email->getBcc()) {
            $payload['bcc'] = $this->stringify($email->getBcc());
        }
        if ($email->getReplyTo()) {
            $payload['reply_to'] = $this->stringify($email->getReplyTo());
        }

        $attachments = [];
        foreach ($email->getAttachments() as $attachment) {
            $headers = $attachment->getPreparedHeaders();
            $filename = $headers->getHeaderParameter('Content-Disposition', 'filename')
                ?? $headers->getHeaderParameter('Content-Type', 'name')
                ?? '';
            $attachments[] = [
                'filename' => $filename,
                'content' => base64_encode($attachment->getBodyAsString()),
            ];
        }
        if ($attachments) {
            $payload['attachments'] = $attachments;
        }

        $client = new Client([
            'timeout' => 20,
            'connect_timeout' => 10,
            'curl' => $this->curlResolveOptions(),
        ]);

        $lastError = '';
        // 3 tentatives : le réseau intercontinentale peut être intermittent.
        for ($attempt = 1; $attempt <= 3; $attempt++) {
            try {
                $response = $client->post("{$this->baseUrl}/emails", [
                    'headers' => [
                        'Authorization' => 'Bearer ' . $this->apiKey,
                        'Accept' => 'application/json',
                    ],
                    'json' => $payload,
                ]);

                if ($response->getStatusCode() < 300) {
                    return; // envoyé
                }

                $lastError = 'Resend API error ' . $response->getStatusCode() . ': ' . (string) $response->getBody();
            } catch (\GuzzleHttp\Exception\TransferException $e) {
                $lastError = $e->getMessage();
            }

            if ($attempt < 3) {
                usleep(400000); // 400 ms avant retry
            }
        }

        throw new Exception($lastError);
    }

    /**
     * Contourne les timeouts de résolution DNS de cURL (rencontrés sur certains
     * environnements Windows/PHP et réseaux intermittents) : l'IP est résolue
     * par gethostbynamel (fiable) et injectée via CURLOPT_RESOLVE — le SNI/TLS
     * reste préservé, c'est transparent pour Resend.
     *
     * @return array<int, int|string>
     */
    protected function curlResolveOptions(): array
    {
        $host = parse_url($this->baseUrl, PHP_URL_HOST) ?: 'api.resend.com';
        $ips = @gethostbynamel($host) ?: [];
        if (! $ips) {
            return [];
        }

        // Une entrée CURLOPT_RESOLVE par IP : "hôte:443:ip"
        $resolve = array_map(fn (string $ip) => "{$host}:443:{$ip}", $ips);

        return [
            CURLOPT_RESOLVE => $resolve,
            CURLOPT_IPRESOLVE => CURL_IPRESOLVE_V4,
        ];
    }

    /**
     * Destinataires "to" réels (hors cc/bcc déjà passés séparément).
     *
     * @return Address[]
     */
    protected function recipients(Email $email, Envelope $envelope): array
    {
        return array_values(array_filter(
            $envelope->getRecipients(),
            fn (Address $address) => ! in_array($address, array_merge($email->getCc(), $email->getBcc()), true),
        ));
    }

    /** @param  Address[]  $addresses */
    protected function stringify(array $addresses): array
    {
        return array_map(fn (Address $a) => $a->toString(), $addresses);
    }

    public function __toString(): string
    {
        return 'resend-http';
    }
}
