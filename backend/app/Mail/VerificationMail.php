<?php

namespace App\Mail;

use App\Models\User;
use Illuminate\Bus\Queueable;
use Illuminate\Mail\Mailable;
use Illuminate\Queue\SerializesModels;
use Illuminate\Support\Facades\URL;

class VerificationMail extends Mailable
{
    use Queueable, SerializesModels;

    public function __construct(public User $user) {}

    public function build(): self
    {
        $url = URL::temporarySignedRoute(
            'verification.verify',
            now()->addHours(24),
            ['id' => $this->user->id, 'hash' => sha1($this->user->email)]
        );

        $html = '<h2>Bienvenue sur SafeRide AI</h2>'
            . '<p>Bonjour ' . e($this->user->prenom) . ',</p>'
            . '<p>Merci de vérifier votre adresse email en cliquant sur le lien ci-dessous :</p>'
            . '<p><a href="' . e($url) . '">' . e($url) . '</a></p>'
            . '<p>Ce lien expire dans 24h.</p>';

        return $this->subject('Vérifiez votre email — SafeRide AI')->html($html);
    }
}
