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
     * S'applique aux anomalies directes (SPEED, MOVEMENT_LOSS).
     */
    public const ANOMALY_RESPONSE_TIMEOUT_MINUTES = 5;

    /**
     * Détour / arrêt prolongé : escalade en deux temps sur le PASSAGER —
     * aucune réponse 10 min après la fenêtre ET situation toujours en cours
     * => 2e notification (rappel, « notre préoccupation ») ; toujours aucune
     * réponse 10 min après le rappel => SOS automatique. Si la situation se
     * règle entre-temps (trajet revenu sur l'itinéraire / véhicule reparti),
     * la vérification se clôture sans SOS.
     */
    public const WELLBEING_FIRST_DEADLINE_MINUTES = 10;
    public const WELLBEING_ESCALATION_MINUTES = 10;

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
            'declenchement' => 'ANALYSE_IA',
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
     * Watchdog planifié (anomaly:check-timeouts, chaque minute) :
     * - SPEED / MOVEMENT_LOSS : SOS automatique après 5 min sans réponse.
     * - DETOUR / STOP (bien-être passager) : escalade en deux temps —
     *   1re fenêtre sans réponse depuis 10 min ET situation toujours en cours
     *   => rappel (2e notification) ; 10 min après le rappel, toujours aucune
     *   réponse => SOS automatique. Si la situation s'est réglée (retour sur
     *   l'itinéraire / véhicule reparti), la vérification se clôture sans SOS.
     */
    public static function processTimeouts(): int
    {
        $ai = app(AiService::class);

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

            $wellbeing = in_array($verification->anomaly_type, ['DETOUR', 'STOP'], true);

            if ($wellbeing) {
                // La cause de la notification a-t-elle disparu depuis ?
                if (! $ai->situationOngoing($verification)) {
                    $verification->update(['statut' => 'CONFIRMEE', 'responded_at' => now()]);

                    Notification::create([
                        'user_id' => $user->id,
                        'type' => 'ANOMALIE_VERIFICATION',
                        'titre' => 'Situation régularisée',
                        'message' => 'La situation surveillée s\'est normalisée : aucune alerte envoyée.',
                    ]);

                    continue;
                }

                if ($verification->rappel_at === null) {
                    // 1er délai écoulé -> 2e notification (rappel), pas encore de SOS.
                    if ($verification->created_at->lte(now()->subMinutes(self::WELLBEING_FIRST_DEADLINE_MINUTES))) {
                        $verification->update(['rappel_at' => now()]);

                        Notification::create([
                            'user_id' => $user->id,
                            'type' => 'ANOMALIE_VERIFICATION',
                            'titre' => 'SafeRide s\'inquiète — répondez',
                            'message' => $verification->description . ' Sans réponse de votre part dans 10 minutes, '
                                . 'une alerte SOS sera envoyée automatiquement à vos contacts.',
                        ]);
                    }

                    continue;
                }

                // Rappel envoyé depuis ≥ 10 min et toujours sans réponse -> SOS.
                if ($verification->rappel_at->gt(now()->subMinutes(self::WELLBEING_ESCALATION_MINUTES))) {
                    continue;
                }
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
