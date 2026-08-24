<?php

namespace App\Http\Controllers;

use App\Models\EmergencyContact;
use App\Models\EmergencyService;
use App\Models\ManagerAssignment;
use App\Models\Notification;
use App\Models\SosAlert;
use App\Models\Trip;
use App\Models\User;
use App\Models\VoiceSecurityProfile;
use App\Mail\SosAlertMail;
use App\Services\SmsService;
use App\Services\WhatsappService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Mail;

class SosController extends Controller
{
    public function create(Request $request): JsonResponse
    {
        $data = $request->validate([
            'trip_id' => 'required|exists:trips,id',
            'latitude' => 'required|numeric|between:-90,90',
            'longitude' => 'required|numeric|between:-180,180',
            'declenchement' => 'required|in:VOCAL,BOUTON',
            'keyword' => 'nullable|string|max:40',
            'empreinte' => 'nullable',
        ]);
        // Harmonie: empreinte peut être array ECAPA (List<double>) ou string token repli
        if (isset($data['empreinte']) && is_array($data['empreinte'])) {
            $request->validate(['empreinte.*' => 'numeric']);
        }

        $trip = Trip::where('id', $data['trip_id'])
            ->where('passager_id', $request->user()->id)
            ->where('statut', 'EN_COURS')
            ->first();

        if (! $trip) {
            return response()->json(['message' => 'Aucun trajet actif pour cet utilisateur'], 422);
        }

        // P2-9 : anti double SOS / replay 30s
        $recent = SosAlert::where('trip_id', $trip->id)
            ->where('passager_id', $request->user()->id)
            ->where('created_at', '>', now()->subSeconds(30))
            ->whereNotIn('statut', ['RESOLU', 'CLOTE', 'FAUSSE_ALERTE'])
            ->first();
        if ($recent) {
            return response()->json(['message' => 'Alerte déjà envoyée il y a moins de 30s — anti-spam', 'sos' => $recent], 429);
        }

        // Vérification SOS vocal : mot-clé + empreinte vocale (Point 9)
        $verification = $this->verifyVoice($request->user(), $data);
        $statut = $verification['statut'];

        $sos = SosAlert::create([
            'trip_id' => $trip->id,
            'passager_id' => $request->user()->id,
            'declenchement' => $data['declenchement'],
            'latitude' => $data['latitude'],
            'longitude' => $data['longitude'],
            'heure_detection' => now(),
            'statut' => $statut,
            'details' => $verification['details'],
        ]);

        $alertsSent = $this->dispatchAlerts($sos);
        $this->assignManager($sos);

        $transmission = $this->notifyAll($request, $sos, $trip);

        $message = match (true) {
            $data['declenchement'] === 'BOUTON' => $transmission['en_attente']
                ? 'Alerte bouton reçue. En attente de connexion.'
                : 'Alerte bouton transmise',
            $verification['details']['verification_passed'] ?? false => 'Alerte vocale vérifiée et transmise',
            default => 'Alerte vocale reçue mais non vérifiée — en cours de vérification.',
        };

        // Contacts d'urgence avec téléphone pour envoi SMS/WhatsApp natif côté mobile (fallback)
        $contacts = EmergencyContact::where('user_id', $request->user()->id)
            ->whereNotNull('telephone')
            ->where('telephone', '!=', '')
            ->select('nom', 'telephone', 'whatsapp_telephone', 'email')
            ->get();

        return response()->json([
            'message' => $message,
            'sos' => $sos->load('emergencyNotifications'),
            'emergency_contacts' => $contacts,
            'sms_message' => $this->smsMessage($sos, $trip, null),
            'alerts_sent' => $alertsSent, // P1-3 : canaux réellement envoyés vs tentés
        ], 201);
    }

    /**
     * Vérifie un déclenchement SOS vocal (mot-clé + empreinte).
     * BOUTON = déclenchement immédiat (fallback). VOCAL = vérifié si mot-clé
     * et empreinte correspondent au profil du passager.
     */
    protected function verifyVoice(User $user, array $data): array
    {
        if ($data['declenchement'] === 'BOUTON') {
            return [
                'statut' => 'DECLENCHE',
                'details' => [
                    'triggered_by' => 'bouton',
                    'verification_passed' => true,
                ],
            ];
        }

        $profile = VoiceSecurityProfile::where('user_id', $user->id)->first();

        $keywordMatch = $profile
            && $profile->mot_securite
            && $data['keyword']
            && strcasecmp(trim($data['keyword']), $profile->mot_securite) === 0;

        $voiceMatch = false;
        if ($profile && $profile->empreinte_vocale && isset($data['empreinte'])) {
            $stored = json_decode($profile->empreinte_vocale, true);
            $incoming = $data['empreinte'];
            // P1-4 : validation stricte 192 valeurs
            if (is_array($stored) && is_array($incoming) && $stored !== [] && $incoming !== []) {
                if (count($stored) !== 192 || count($incoming) !== 192) {
                    \Log::warning('Empreinte taille invalide', ['stored' => count($stored), 'incoming' => count($incoming)]);
                } elseif (is_numeric($stored[0] ?? null) && is_numeric($incoming[0] ?? null)) {
                    $voiceMatch = $this->cosineSimilarity($stored, $incoming) >= self::VOICE_SIMILARITY_THRESHOLD;
                }
            } elseif (is_string($stored) && is_string($incoming)) {
                // Deux tokens sha256 64 hex -> hash_equals
                if (preg_match('/^[a-f0-9]{64}$/i', $stored) && preg_match('/^[a-f0-9]{64}$/i', $incoming)) {
                    $voiceMatch = hash_equals($stored, $incoming);
                }
            }
        }

        $passed = $keywordMatch && $voiceMatch;

        return [
            'statut' => $passed ? 'DECLENCHE' : 'VERIFICATION',
            'details' => [
                'triggered_by' => 'vocal',
                'keyword_detected' => (bool) $keywordMatch,
                'voiceprint_match' => (bool) $voiceMatch,
                'verification_passed' => $passed,
            ],
        ];
    }

    /** Seuil de similarité cosinus entre deux embeddings de voix (0.5 = voix proche). */
    private const VOICE_SIMILARITY_THRESHOLD = 0.5;

    protected function cosineSimilarity(array $a, array $b): float
    {
        if (count($a) !== count($b) || $a === []) {
            return 0.0;
        }

        $dot = 0.0;
        $normA = 0.0;
        $normB = 0.0;

        foreach ($a as $i => $value) {
            $dot += $value * $b[$i];
            $normA += $value * $value;
            $normB += $b[$i] * $b[$i];
        }

        if ($normA <= 0.0 || $normB <= 0.0) {
            return 0.0;
        }

        return $dot / (sqrt($normA) * sqrt($normB));
    }

    public function show(Request $request, int $id): JsonResponse
    {
        $sos = SosAlert::with('trip', 'passager', 'emergencyNotifications')
            ->findOrFail($id);

        return response()->json(['sos' => $sos]);
    }

    public function myAlerts(Request $request): JsonResponse
    {
        $alerts = SosAlert::with('trip')
            ->where('passager_id', $request->user()->id)
            ->latest()
            ->paginate(15);

        return response()->json(['alerts' => $alerts]);
    }

    public function resolve(Request $request, int $id): JsonResponse
    {
        $data = $request->validate([
            'statut' => 'required|in:RESOLU,FAUSSE_ALERTE,EN_COURS',
            'details' => 'nullable|array',
        ]);

        $sos = SosAlert::findOrFail($id);
        $sos->update([
            'statut' => $data['statut'],
            'details' => array_merge((array) $sos->details, $data['details'] ?? []),
        ]);

        return response()->json([
            'message' => 'Enregistré',
            'sos' => $sos,
        ]);
    }

    protected function dispatchAlerts(SosAlert $sos): array
    {
        $trip = $sos->trip;
        $smsMessage = $this->smsMessage($sos, $trip, null);
        $smsService = app(SmsService::class);
        $waService = app(WhatsappService::class);

        $perContact = [];

        // Contacts d'urgence -> SMS TOUJOURS (obligatoire) + WhatsApp si sur WA + email
        EmergencyContact::where('user_id', $sos->passager_id)
            ->get()
            ->each(function (EmergencyContact $contact) use ($sos, $trip, $smsMessage, $smsService, $waService, &$perContact) {
                $smsSent = false;
                $smsTried = false;
                $waSent = false;
                $waTried = false;
                $emailSent = false;
                $canaux = [];

                // 1) SMS — canal obligatoire
                if ($contact->telephone) {
                    $smsTried = true;
                    $smsSent = $smsService->send($contact->telephone, $smsMessage);
                    $canaux[] = $smsSent ? 'SMS (' . $contact->telephone . ')' : 'SMS tenté (' . $contact->telephone . ')';
                }

                // 2) WhatsApp — complémentaire si numéro sur WhatsApp
                $waNumber = $contact->whatsapp_telephone ?: $contact->telephone;
                if ($waNumber && $waService->ready()) {
                    $waTried = true;
                    if ($waService->isOnWhatsApp($waNumber)) {
                        $waSent = $waService->send($waNumber, $smsMessage);
                        if ($waSent) $canaux[] = 'WhatsApp (' . $waNumber . ')';
                    } else {
                        \Illuminate\Support\Facades\Log::info('Contact non WhatsApp, SMS seul', ['to' => $waNumber]);
                    }
                }

                // 3) Email
                if ($contact->email) {
                    try {
                        Mail::to($contact->email)->send(new SosAlertMail($sos, $trip, $contact->nom));
                        $emailSent = true;
                        $canaux[] = 'email (' . $contact->email . ')';
                    } catch (\Throwable $e) {}
                }

                $perContact[] = [
                    'contact_id' => $contact->id,
                    'nom' => $contact->nom,
                    'telephone' => $contact->telephone,
                    'whatsapp' => $waNumber,
                    'sms_tried' => $smsTried,
                    'sms_sent' => $smsSent,
                    'whatsapp_tried' => $waTried,
                    'whatsapp_sent' => $waSent,
                    'email_sent' => $emailSent,
                    'canaux' => $canaux,
                ];

                Notification::create([
                    'user_id' => $sos->passager_id,
                    'type' => 'SOS',
                    'titre' => 'SOS en cours — Contact ' . $contact->nom,
                    'message' => 'Votre contact d\'urgence ' . $contact->nom
                        . (count($canaux) > 0 ? ' a été notifié par ' . implode(' et ', $canaux) . ($smsSent ? '' : ' (SMS en attente de crédit, WhatsApp/email actifs)') : ' n\'a pas pu être notifié (aucun canal configuré).'),
                ]);
            });

        // Services d'urgence
        EmergencyService::get()->each(function (EmergencyService $service) use ($sos, $trip) {
            if ($service->email) {
                try { Mail::to($service->email)->send(new SosAlertMail($sos, $trip, $service->nom)); } catch (\Throwable $e) {}
            }
            $sos->emergencyNotifications()->create(['emergency_service_id' => $service->id, 'notifie_le' => now(), 'statut' => 'TRANSMISE']);
        });

        $summary = [
            'contacts_total' => count($perContact),
            'sms_sent' => collect($perContact)->where('sms_sent', true)->count(),
            'sms_tried' => collect($perContact)->where('sms_tried', true)->count(),
            'whatsapp_sent' => collect($perContact)->where('whatsapp_sent', true)->count(),
            'email_sent' => collect($perContact)->where('email_sent', true)->count(),
        ];

        return ['per_contact' => $perContact, 'summary' => $summary];
    }

    /**
     * Message SMS court envoyé au contact d'urgence lors d'un SOS.
     */
    protected function smsMessage(SosAlert $sos, Trip $trip, ?EmergencyContact $contact): string
    {
        $passager = $sos->passager;

        $message = 'URGENT SafeRide : ' . ($passager?->prenom ?? 'un passager') . ' '
            . ($passager?->nom ?? '') . " a déclenché une alerte SOS.";

        if ($sos->latitude && $sos->longitude) {
            $message .= ' Position : https://maps.google.com/?q='
                . $sos->latitude . ',' . $sos->longitude;
        }

        if ($trip->destination_address) {
            $message .= ' Destination : ' . $trip->destination_address;
        }

        if ($contact) {
            $message .= ' — ' . $contact->nom;
        }

        return $message;
    }

    protected function assignManager(SosAlert $sos): void
    {
        $manager = User::whereHas('roles', fn ($q) => $q->where('slug', 'gestionnaire'))
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
                'titre' => 'Nouveau dossier SOS attribué',
                'message' => 'Une alerte SOS est attribuée à votre compte. Position : ' . $sos->latitude . ', ' . $sos->longitude,
            ]);

            if ($manager->email) {
                try {
                    Mail::to($manager->email)->send(new SosAlertMail($sos, $sos->trip, $manager->nom));
                } catch (\Throwable $e) {
                }
            }
        }
    }

    protected function notifyAll(Request $request, SosAlert $sos, Trip $trip): array
    {
        $withNetwork = true; // placeholder réseau ; en production : vérifier la connectivité réelle

        // Une alerte non vérifiée (VERIFICATION) reste en attente de confirmation
        if ($sos->statut === 'VERIFICATION') {
            return ['en_attente' => false, 'verification' => false];
        }

        $sos->update(['statut' => $withNetwork ? 'NOTIFIE' : 'DECLENCHE']);

        return ['en_attente' => ! $withNetwork];
    }
}