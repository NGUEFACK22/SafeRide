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
 * Transport Brevo (ex-Sendinblue) SANS SDK : appelle l'API HTTP directement
 * https://api.brevo.com/v3/smtp/email (port 443 - HTTPS, JAMAIS bloqué par
 * Render, contrairement aux ports SMTP 587/465 qui timeout au niveau TCP).
 *
 * C'est LE canal fiable pour Render : clé API Brevo (xkeysib-...) envoyée via
 * l'en-tête "api-key", pas de SMTP, pas de domaine exigé (expéditeur vérifié
 * par code suffit).
 *
 * Enregistré comme mailer "brevo-http" dans config/mail.php :
 *   MAIL_MAILER=brevo-http + BREVO_API_KEY=xkeysib-...
 */
class BrevoHttpTransport extends AbstractTransport
{
    public function __construct(
        protected string $apiKey,
        protected string $baseUrl = 'https://api.brevo.com',
    ) {
        parent::__construct();
    }

    protected function doSend(SentMessage $message): void
    {
        $email = MessageConverter::toEmail($message->getOriginalMessage());
        $envelope = $message->getEnvelope();

        $sender = $envelope->getSender();
        $payload = [
            'sender' => [
                'email' => $sender->getAddress(),
                'name' => $sender->getName(),
            ],
            'to' => $this->addresses($this->recipients($email, $envelope)),
            'subject' => $email->getSubject(),
        ];

        if ($email->getHtmlBody()) {
            $payload['htmlContent'] = $email->getHtmlBody();
        } elseif ($email->getTextBody()) {
            $payload['textContent'] = $email->getTextBody();
        } else {
            $payload['textContent'] = $email->getBody()->toString();
        }

        if ($email->getCc()) {
            $payload['cc'] = $this->addresses($email->getCc());
        }
        if ($email->getBcc()) {
            $payload['bcc'] = $this->addresses($email->getBcc());
        }
        if ($email->getReplyTo()) {
            $payload['replyTo'] = $this->addresses($email->getReplyTo());
        }

        $attachments = [];
        foreach ($email->getAttachments() as $attachment) {
            $headers = $attachment->getPreparedHeaders();
            $filename = $headers->getHeaderParameter('Content-Disposition', 'filename')
                ?? $headers->getHeaderParameter('Content-Type', 'name')
                ?? 'piece-jointe';
            $attachments[] = [
                'name' => $filename,
                'content' => base64_encode($attachment->getBodyAsString()),
            ];
        }
        if ($attachments) {
            $payload['attachment'] = $attachments;
        }

        $client = new Client([
            'timeout' => 20,
            'connect_timeout' => 10,
            'curl' => $this->curlResolveOptions(),
        ]);

        $lastError = '';
        // 3 tentatives : le réseau intercontinental peut être intermittent.
        for ($attempt = 1; $attempt <= 3; $attempt++) {
            try {
                $response = $client->post("{$this->baseUrl}/v3/smtp/email", [
                    'headers' => [
                        'api-key' => $this->apiKey,
                        'Accept' => 'application/json',
                    ],
                    'json' => $payload,
                ]);

                if ($response->getStatusCode() < 300) {
                    return; // envoyé
                }

                $lastError = 'Brevo API ' . $response->getStatusCode() . ': ' . (string) $response->getBody();
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
    protected function addresses(array $addresses): array
    {
        return array_map(fn (Address $a) => [
            'email' => $a->getAddress(),
            // Brevo exige un `name` NON vide dans chaque `to` (erreur 400
            // "name is missing in to" sinon). Laravel le laisse vide quand le
            // contact de secours n'a pas de nom affiché -> on met un défaut.
            'name' => $a->getName() ?: 'Contact Secours SafeRide',
        ], $addresses);
    }

    /**
     * Contourne les timeouts de résolution DNS de cURL (rencontrés sur certains
     * environnements Windows/PHP et réseaux intermittents) : l'IP est résolue
     * par gethostbynamel (fiable) et injectée via CURLOPT_RESOLVE — le SNI/TLS
     * reste préservé, c'est transparent pour Brevo.
     *
     * @return array<int, int|string>
     */
    protected function curlResolveOptions(): array
    {
        $host = parse_url($this->baseUrl, PHP_URL_HOST) ?: 'api.brevo.com';
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

    public function __toString(): string
    {
        return 'brevo-http';
    }
}
