<?php

namespace App\Mail;

use App\Models\SosAlert;
use App\Models\Trip;
use Illuminate\Bus\Queueable;
use Illuminate\Mail\Mailable;
use Illuminate\Queue\SerializesModels;

class SosAlertMail extends Mailable
{
    use Queueable, SerializesModels;

    public function __construct(
        public SosAlert $sos,
        public ?Trip $trip,
        public string $recipientName = '',
    ) {
    }

    public function build(): self
    {
        $trip = $this->trip;
        $passager = $this->sos->passager;
        $transporteur = $trip?->transporteur;

        $html = '<h2>🚨 Alerte SOS SafeRide</h2>'
            . '<p>Une alerte SOS a été déclenchée et transmise automatiquement par la plateforme.</p>'
            . '<ul>'
            . '<li><strong>Passager :</strong> ' . e($passager?->prenom . ' ' . $passager?->nom) . '</li>'
            . '<li><strong>Moyen de déclenchement :</strong> ' . e($this->sos->declenchement) . '</li>'
            . '<li><strong>Statut :</strong> ' . e($this->sos->statut) . '</li>'
            . '<li><strong>Position (lat, lng) :</strong> ' . e($this->sos->latitude . ', ' . $this->sos->longitude) . '</li>'
            . '<li><strong>Heure de détection :</strong> ' . e((string) $this->sos->heure_detection) . '</li>'
            . '<li><strong>Trajet # :</strong> ' . e((string) ($trip?->id ?? '—')) . '</li>'
            . '<li><strong>Transporteur :</strong> ' . e(($transporteur?->prenom . ' ' . $transporteur?->nom) ?: '—') . '</li>'
            . '<li><strong>Véhicule # :</strong> ' . e((string) ($trip?->vehicle_id ?? '—')) . '</li>'
            . '</ul>'
            . '<p>Merci de prendre les mesures appropriées.</p>';

        return $this->subject('🚨 Alerte SOS SafeRide — intervention requise')
            ->html($html);
    }
}
