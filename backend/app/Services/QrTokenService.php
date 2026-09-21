<?php

namespace App\Services;

use App\Models\User;
use App\Models\Vehicle;
use Illuminate\Support\Str;

/**
 * Tokens de QR Code SafeRide.
 *
 * Un QR est un token signé HMAC-SHA256 (clé app.key) portant un payload JSON
 * identifiant le véhicule et son transporteur, avec un aléa anti-collision et
 * une date d'expiration. Le scan refusé si : signature invalide, payload
 * incohérent avec le véhicule en base, ou expiration dépassée — ce qui rend
 * le clonage/edit d'un QR visuellement inopérant.
 *
 * Validité = QR_VALIDITY_HOURS (24 h par défaut). Le QR n'est PAS consommé par
 * un scan : il reste réutilisable plusieurs fois pendant sa fenêtre de validité,
 * puis est remplacé automatiquement (rotation) ou manuellement.
 *
 * Format : base64( payload_json . '.' . hmac_sha256(payload_json) )
 * (inchangé depuis l'origine pour ne pas invalider les QR déjà imprimés)
 */
class QrTokenService
{
    public const TTL_HOURS = 24;

    /**
     * Durée de validité d'un QR en heures (défaut 24h, surchargeable par
     * l'environnement QR_VALIDITY_HOURS pour les tests).
     */
    public static function ttlHours(): int
    {
        $hours = (int) env('QR_VALIDITY_HOURS', self::TTL_HOURS);

        return $hours > 0 ? $hours : self::TTL_HOURS;
    }

    /**
     * Génère un token signé pour un véhicule.
     */
    public function generate(Vehicle $vehicle): string
    {
        $transporteur = $vehicle->relationLoaded('transporteur')
            ? $vehicle->transporteur
            : User::find($vehicle->transporteur_id);

        $payload = json_encode([
            'vid' => $vehicle->id,
            'immatriculation' => $vehicle->immatriculation,
            'transporteur_id' => $vehicle->transporteur_id,
            'transporteur_nom' => $transporteur?->nom ?? '',
            'transporteur_prenom' => $transporteur?->prenom ?? '',
            'transporteur_fullname' => trim(($transporteur?->prenom ?? '') . ' ' . ($transporteur?->nom ?? '')),
            'n' => Str::random(12),
            'exp' => now()->addHours(self::ttlHours())->timestamp,
        ]);

        return base64_encode($payload . '.' . $this->sign($payload));
    }

    /**
     * Décode et VERIFIE un token. Renvoie le payload (array) si la signature
     * et la date d'expiration sont valides, null sinon.
     */
    public function verify(string $token): ?array
    {
        $raw = base64_decode($token, true);

        if ($raw === false) {
            return null;
        }

        // Le séparateur est le DERNIER point (une signature hex n'en contient
        // jamais ; un nom de transporteur peut en contenir un).
        $sep = strrpos($raw, '.');

        if ($sep === false || $sep === 0 || $sep === strlen($raw) - 1) {
            return null;
        }

        $payload = substr($raw, 0, $sep);
        $signature = substr($raw, $sep + 1);

        if (! hash_equals($this->sign($payload), $signature)) {
            return null;
        }

        $data = json_decode($payload, true);

        if (! is_array($data) || empty($data['vid'])) {
            return null;
        }

        if (isset($data['exp']) && (int) $data['exp'] < now()->timestamp) {
            return null;
        }

        return $data;
    }

    protected function sign(string $payload): string
    {
        return hash_hmac('sha256', $payload, (string) config('app.key'));
    }
}
