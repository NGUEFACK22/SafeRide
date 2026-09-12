<?php

namespace App\Http\Controllers;

use App\Models\AnomalyVerification;
use App\Models\SosAlert;
use App\Services\AiService;
use App\Services\SmsService;
use App\Services\WhatsappService;
use App\Mail\SosAlertMail;
use App\Models\EmergencyContact;
use App\Models\ManagerAssignment;
use App\Models\Notification;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Mail;

class AnomalyVerificationController extends Controller
{
    /**
     * Délai (min) laissé à chaque partie pour répondre à une vérification
     * d'anomalie avant déclenchement automatique d'un SOS sur le non-répondant.
     */
    public const ANOMALY_RESPONSE_TIMEOUT_MINUTES = 3;

    /**
     * Vérifications en attente pour l'utilisateur connecté.
     */
    public function index(Request $request): JsonResponse
    {
        $pending = AnomalyVerification::where('user_id', $request->user()->id)
            ->where('statut', 'EN_ATTENTE')
            ->with('trip')
            ->latest()
            ->get();

        return response()->json(['verifications' => $pending]);
    }

    /**
     * L'utilisateur répond à une vérification d'anomalie.
     * - "normal" : la course continue, la vérification est clôturée.
     * - "abnormal" : un SOS est déclenché automatiquement.
     */
    public function respond(Request $request, int $id): JsonResponse
    {
        $data = $request->validate([
            'response' => 'required|in:normal,abnormal',
        ]);

        $verification = AnomalyVerification::where('user_id', $request->user()->id)
            ->findOrFail($id);

        if ($verification->statut !== 'EN_ATTENTE') {
            return response()->json(['message' => 'Déjà traité.'], 409);
        }

        if ($data['response'] === 'normal') {
            $verification->update([
                'statut' => 'CONFIRMEE',
                'responded_at' => now(),
            ]);

            Notification::create([
                'user_id' => $request->user()->id,
                'type' => 'ANOMALIE_VERIFICATION',
                'titre' => 'Anomalie confirmée normale',
                'message' => 'La situation a été confirmée normale. Course poursuivie.',
            ]);

            return response()->json(['message' => 'Confirmé. La course continue.']);
        }

        // abnormal → déclencher le processus SOS
        $verification->update([
            'statut' => 'ALARME',
            'responded_at' => now(),
        ]);

        $this->triggerSosFromAnomaly($verification, $request->user());

        return response()->json(['message' => 'SOS déclenché suite à l\'anomalie signalée.']);
    }

    /**
     * Déclenche un SOS à partir d'une vérification d'anomalie.
     * Même logique que SosController::create mais déclenché automatiquement.
     */
    protected function triggerSosFromAnomaly(AnomalyVerification $verification, $user): void
    {
        $trip = $verification->trip;

        // Position du dernier point GPS du trajet
        $lastLoc = $trip?->locations()->orderByDesc('captured_at')->first();
        $lat = $lastLoc?->latitude ?? ($trip?->start_latitude ?? 0);
        $lng = $lastLoc?->longitude ?? ($trip?->start_longitude ?? 0);

        $sos = SosAlert::create([
            'trip_id' => $trip?->id,
            'passager_id' => $user->id,
            'destination' => $trip?->destination_address,
            'declenchement' => 'BOUTON',
            'latitude' => $lat,
            'longitude' => $lng,
            'heure_detection' => now(),
            'statut' => 'DECLENCHE',
            'details' => [
                'triggered_by' => 'anomaly_verification',
                'anomaly_type' => $verification->anomaly_type,
                'anomaly_description' => $verification->description,
                'auto_triggered' => true,
                'targeted_user_id' => $user->id,
            ],
        ]);

        $smsMessage = 'URGENT SafeRide : ' . ($user->prenom ?? '') . ' '
            . ($user->nom ?? '') . " a déclenché une alerte SOS automatique "
            . "(anomalie: {$verification->anomaly_type}).";

        if ($lat && $lng) {
            $smsMessage .= ' Position : https://maps.google.com/?q=' . $lat . ',' . $lng;
        }

        if ($trip?->destination_address) {
            $smsMessage .= ' Destination : ' . $trip->destination_address;
        }

        // Envoyer SMS + WhatsApp aux contacts d'urgence
        $smsService = app(SmsService::class);
        $waService = app(WhatsappService::class);

        EmergencyContact::where('user_id', $user->id)
            ->get()
            ->each(function (EmergencyContact $contact) use ($sos, $smsMessage, $smsService, $waService) {
                if ($contact->telephone) {
                    $smsService->send($contact->telephone, $smsMessage);
                }

                $waNumber = $contact->whatsapp_telephone ?: $contact->telephone;
                if ($waNumber && $waService->ready() && $waService->isOnWhatsApp($waNumber)) {
                    $waService->send($waNumber, $smsMessage);
                }

                if ($contact->email) {
                    try {
                        Mail::to($contact->email)->send(new SosAlertMail($sos, $sos->trip, $contact->nom));
                    } catch (\Throwable $e) {
                    }
                }

                Notification::create([
                    'user_id' => $user->id,
                    'type' => 'SOS',
                    'titre' => 'SOS automatique — anomalie détectée',
                    'message' => 'Alerte SOS déclenchée automatiquement suite à l\'anomalie : '
                        . $verification->anomaly_type,
                ]);
            });

        // Assigner un gestionnaire
        $manager = \App\Models\User::whereHas('roles', fn ($q) => $q->where('slug', 'gestionnaire'))
            ->withCount(['managerAssignments as ouvertes' => fn ($q) => $q->where('statut', '!=', 'CLOTURE')])
            ->orderBy('ouvertes')
            ->first();

        if ($manager) {
            ManagerAssignment::create([
                'manager_id' => $manager->id,
                'dossier_type' => 'SOS',
                'dossier_id' => $sos->id,
                'statut' => 'ATTRIBUE',
            ]);

            Notification::create([
                'user_id' => $manager->id,
                'type' => 'SOS',
                'titre' => 'SOS automatique — anomalie',
                'message' => 'SOS déclenché automatiquement (anomalie: '
                    . $verification->anomaly_type . ') — position: ' . $lat . ', ' . $lng,
            ]);

            if ($manager->email) {
                try {
                    Mail::to($manager->email)->send(new SosAlertMail($sos, $sos->trip, $manager->nom));
                } catch (\Throwable $e) {
                }
            }
        }
    }

    /**
     * Déclenche les SOS pour les vérifications en timeout (> 3 min sans
     * réponse). Chaque vérification cible une seule partie (passager ou
     * transporteur) : le SOS est donc lancé sur la personne qui n'a pas
     * répondu. Appelé par la commande schedulée anomaly:check-timeouts.
     */
    public static function processTimeouts(): int
    {
        $timeouts = AnomalyVerification::where('statut', 'EN_ATTENTE')
            ->where('created_at', '<', now()->subMinutes(self::ANOMALY_RESPONSE_TIMEOUT_MINUTES))
            ->get();

        $count = 0;

        foreach ($timeouts as $verification) {
            $user = $verification->user;
            if (! $user) {
                $verification->update(['statut' => 'ALARME']);
                continue;
            }

            $controller = new self();
            $controller->triggerSosFromAnomaly($verification, $user);

            // Marque la vérification comme traitée : évite de re-déclencher
            // un SOS à chaque exécution de la commande.
            $verification->update([
                'statut' => 'ALARME',
                'responded_at' => now(),
            ]);
            $count++;
        }

        return $count;
    }
}
