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
        $data = $this->sos->forNotification($this->trip, $this->recipientName);
        $salutation = $data['recipient'] !== ''
            ? 'Bonjour ' . e($data['recipient']) . ','
            : 'Bonjour,';

        $mapLink = e($data['maps_link']);
        $mapAnchor = $mapLink === '—'
            ? '—'
            : '<a href="' . $mapLink . '">' . $mapLink . '</a>';

        $html = '<div style="font-family:Arial,Helvetica,sans-serif;max-width:560px;margin:0 auto;border:1px solid #eee;border-radius:8px;overflow:hidden">'
            . '<div style="background:#d32f2f;color:#fff;padding:16px 20px;font-size:20px;font-weight:bold">🚨 ALERTE SOS – SafeRide AI</div>'
            . '<div style="padding:20px">'
            . '<p>' . $salutation . '</p>'
            . "<p><strong>⚠️ Une alerte SOS vient d'être déclenchée sur SafeRide AI.</strong></p>"
            . '<table cellpadding="6" cellspacing="0" style="border-collapse:collapse;width:100%">'
            . '<tr><td style="border-bottom:1px solid #f0f0f0">👤 <strong>Passager :</strong></td><td style="border-bottom:1px solid #f0f0f0">' . e($data['passager']) . '</td></tr>'
            . '<tr><td style="border-bottom:1px solid #f0f0f0">🚗 <strong>Transporteur :</strong></td><td style="border-bottom:1px solid #f0f0f0">' . e($data['transporteur']) . '</td></tr>'
            . "<tr><td style=\"border-bottom:1px solid #f0f0f0\">🕐 <strong>Heure de l'alerte :</strong></td><td style=\"border-bottom:1px solid #f0f0f0\">" . e($data['heure']) . '</td></tr>'
            . '<tr><td style="border-bottom:1px solid #f0f0f0">📍 <strong>Départ de la course :</strong></td><td style="border-bottom:1px solid #f0f0f0">' . e($data['departure']) . '</td></tr>'
            . '<tr><td style="border-bottom:1px solid #f0f0f0">🏁 <strong>Destination prévue :</strong></td><td style="border-bottom:1px solid #f0f0f0">' . e($data['destination']) . '</td></tr>'
            . '<tr><td style="border-bottom:1px solid #f0f0f0">📌 <strong>Localisation actuelle :</strong></td><td style="border-bottom:1px solid #f0f0f0">' . e($data['current_location']) . '</td></tr>'
            . '<tr><td style="border-bottom:1px solid #f0f0f0">🗺️ <strong>Position GPS :</strong></td><td style="border-bottom:1px solid #f0f0f0">' . $mapAnchor . '</td></tr>'
            . '<tr><td style="border-bottom:1px solid #f0f0f0">🆔 <strong>Identifiant du trajet :</strong></td><td style="border-bottom:1px solid #f0f0f0">' . e($data['trip_id']) . '</td></tr>'
            . '</table>'
            . "<p>Cette alerte indique qu'une situation d'urgence pourrait être en cours. <strong>Veuillez intervenir rapidement ou contacter les services d'urgence si nécessaire.</strong></p>"
            . '<p style="margin-top:20px;color:#888;font-size:13px"><strong>SafeRide AI – Votre sécurité, notre priorité.</strong></p>'
            . '</div>'
            . '</div>';

        return $this->subject('🚨 ALERTE SOS – SafeRide AI — intervention requise')
            ->html($html);
    }
}