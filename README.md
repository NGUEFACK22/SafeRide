# SafeRide AI

Plateforme mobile intelligente de **sécurisation et de traçabilité des déplacements en taxi et moto-taxi** (domaine corrigé : il ne s'agit pas de covoiturage).

SafeRide AI met en relation passagers et transporteurs et assure :
- **Identification des personnes présentes dans un véhicule** via le scan du QR Code unique du transporteur. L'embarquement enregistre automatiquement le passager, le transporteur, le véhicule, la date, l'heure et la position GPS du scan (point de départ).
- **Saisie de la destination et suivi GPS** du trajet, avec **détection d'écart d'itinéraire** et **affichage de l'itinéraire sur une carte** (OpenStreetMap, gratuit sans clé) accessible depuis l'historique des trajets (`GET /trips/{trip}/route`).
- **Déclenchement SOS vocal sécurisé** : mot/phrase de sécurité + empreinte vocale. L'alerte transmet position et détails du trajet aux contacts d'urgence, au gestionnaire et, le cas échéant, aux services d'urgence (email).
- **Signalement d'objets perdus** rattaché au trajet et au transporteur, avec ouverture de **litige** et reconstitution de la **chronologie** par croisement des passagers d'un même véhicule.
- **Vérification d'identité** (CNI / passeport) des passagers et transporteurs via une API KYC spécialisée (**Didit**).
- **Intelligence artificielle** : résumés de trajet, statistiques par rôle et détection d'anomalies (vision gestionnaire + vision globale admin), via **Mistral**.

---

## Architecture

```
┌──────────────┐      HTTPS /api/v1 (Sanctum)      ┌──────────────────────────┐
│  Mobile      │ ───────────────────────────────▶  │  Backend Laravel 12       │
│  Flutter     │ ◀───────────────────────────────  │  (API REST + services)    │
│  (offline +  │                                   ├──────────────────────────┤
│  bg Android) │                                   │  PostgreSQL (Neon cloud)  │
└──────────────┘                                   ├──────────────────────────┤
                                                    │  Mistral (IA) · Didit     │
                                                    │  (KYC) · Mail (SOS)       │
                                                    └──────────────────────────┘
```

- **Backend** : Laravel 12 (PHP 8.2), API REST sous `/api/v1`, authentification par token **Sanctum**.
- **Mobile** : Flutter (mode hors-ligne, service de fond Android pour le SOS).
- **Base de données** : PostgreSQL hébergée sur **Neon** (connexion sécurisée SSL, endpoint dédié).
- **IA** : **Mistral** via endpoint compatible OpenAI (`/chat/completions`).
- **KYC** : **Didit** (`/v3/id-verification/`).
- **Notifications SOS** : email réel (SMTP) + **push Firebase (FCM)** vers l'app en temps réel.

---

## Stack & prérequis

| Composant | Version / outil |
|---|---|
| PHP | 8.2+ (Composer) |
| Backend | Laravel 12, Sanctum, Spatie Laravel Permission |
| Mobile | Flutter 3.x, Android SDK (`image_picker`) |
| Base de données | PostgreSQL (Neon) |
| IA | Mistral (`mistral-small-latest`) |
| KYC | Didit (clé API `x-api-key`) |

Comptes requis pour les fonctionnalités complètes : **Neon** (base), **Mistral** (IA), **Didit** (KYC, nécessite des crédits), **Firebase** (push FCM, gratuit).

---

## Installation

### 1. Backend (Laravel)

```bash
cd backend
composer install
cp .env.example .env          # renseigner DB Neon, AI_*, DIDIT_*, MAIL_*
php artisan key:generate
php artisan migrate --seed    # crée les tables + données de base
php artisan serve             # http://127.0.0.1:8000
```

Variables d'environnement clés (`.env`) :
- `DB_*` : connexion Neon (PgSQL, `DB_SSLMODE=require`, `DB_NEON_ENDPOINT=...`).
- `AI_ENABLED=true`, `AI_API_KEY=...`, `AI_BASE_URL=https://api.mistral.ai/v1`, `AI_MODEL=mistral-small-latest`.
- `DIDIT_API_KEY=...`, `DIDIT_BASE_URL=https://api.didit.me`.
- `MAIL_MAILER=smtp` + `MAIL_HOST`, `MAIL_PORT`, `MAIL_USERNAME`, `MAIL_PASSWORD`, `MAIL_FROM_ADDRESS` : **SMTP réel** pour les emails SOS (ex. Gmail avec mot de passe d'application, gratuit). Par défaut `MAIL_MAILER=log`.
- `FCM_CREDENTIALS_PATH` : chemin du fichier `firebase-service-account.json` (défaut : racine du backend, fichier gitignoré).

### 2. Mobile (Flutter)

```bash
cd mobile
flutter pub get
flutter run                    # émulateur / appareil Android
```

- **URL de l'API** : configurée dans `lib/config/api_config.dart` (émulateur Android → `10.0.2.2` ; appareil/web → `--dart-define=API_BASE_URL=http://<IP_LAN>:8000/api/v1`).
- **Carte (gratuite)** : itinéraire affiché avec **OpenStreetMap** via `flutter_map` — **aucune clé, aucune carte bancaire**. Simple connexion internet pour les tuiles.
- **Push Firebase (FCM)** — config à déposer (fichiers gitignorés, non commités) :
  1. Créer un projet sur https://console.firebase.google.com (paquet `com.saferide.saferide_mobile`).
  2. **Android** : Paramètres → Application Android → télécharger `google-services.json` → le mettre dans `mobile/android/app/`.
  3. **Backend** : Paramètres du projet → Comptes de service → **Générer une nouvelle clé privée** → sauvegarder en `backend/firebase-service-account.json`.
  4. iOS : `GoogleService-Info.plist` dans `mobile/ios/Runner/` (et APNs).

---

## Authentification

Authentification par token Sanctum : `Authorization: Bearer <token>` (obtenu via `POST /auth/login`).
Toute requête non authentifiée renvoie **401 JSON** (jamais de 500).

---

## Endpoints API (`/api/v1`)

### Auth (public)
| Méthode | Route | Description |
|---|---|---|
| POST | `auth/register` | Inscription |
| POST | `auth/login` | Connexion (retourne le token) |
| POST | `auth/logout` | Déconnexion (auth) |
| GET | `auth/profile` | Profil courant (auth) |

### Trajets (auth)
| Méthode | Route | Description |
|---|---|---|
| POST | `trips/start` | Démarrer un trajet |
| POST | `trips/{trip}/confirm-embarquement` | Embarquement par QR du transporteur |
| POST | `trips/{trip}/destination` | Saisir la destination |
| POST | `trips/{trip}/confirm-destination` | Confirmer la destination |
| POST | `trips/{trip}/update-destination` | Modifier en cours de trajet |
| POST | `trips/{trip}/locations` | Envoyer les positions GPS |
| POST | `trips/{trip}/end` | Clôturer (déclenche le résumé IA) |
| GET | `trips/current` | Trajet en cours |
| GET | `trips/history` | Historique |
| GET | `trips/{trip}/route` | Itinéraire décodé (points GPS) pour la carte |

### Véhicules (transporteur, auth)
`vehicles` (CRUD), `vehicles/{id}/qr` (générer QR), `vehicles/{id}/qr/toggle`, `vehicles/{id}/position`.

### Identité (KYC Didit, auth)
| Méthode | Route | Description |
|---|---|---|
| POST | `identity/submit` | Soumettre CNI/passeport (URL **ou** upload) |
| GET | `identity/status` | Statut du dossier |
| GET | `identity/pending` | Dossiers en attente (gestionnaire/admin) |
| PUT | `identity/{id}/review` | Validation manuelle (gestionnaire/admin) |

### SOS (auth)
| Méthode | Route | Description |
|---|---|---|
| POST | `sos` | Déclencher une alerte (email contacts + gestionnaire + services) |
| GET | `sos/my` | Mes alertes |
| GET | `sos/{id}` | Détail (gestionnaire/admin) |
| PUT | `sos/{id}/resolve` | Résolution (gestionnaire/admin) |

### Profil vocal (SOS vocal, auth)
`voice/profile`, `voice/security-word`, `voice/enroll`.

### Assistant IA (auth)
| Méthode | Route | Description |
|---|---|---|
| GET | `ai/summary` | Statistiques personnalisées au rôle (Mistral) |
| GET | `ai/trips/{trip}` | Résumé du trajet (Mistral) |
| GET | `ai/anomalies` | Anomalies (gestionnaire/admin) |

### Incidents (auth)
`lost-items` (CRUD), `lost-items/{id}/chronology` (croisement passagers), `disputes` (CRUD).

### Notifications (auth, in-app)
| Méthode | Route | Description |
|---|---|---|
| GET | `notifications` | 50 notifications récentes + `unread_count` |
| GET | `notifications/unread-count` | Nombre de non-lues (badge, polling) |
| POST | `notifications/{id}/read` | Marquer comme lue |
| POST | `notifications/read-all` | Tout marquer lu |
| POST | `push-token` | Enregistre le token FCM du mobile (push temps réel) |

Toute notification créée côté serveur (SOS, trajet, identité, incidents) est poussée en **temps réel** via **FCM** vers les appareils de l'utilisateur.

### Gestionnaire / Admin
- `manager/dashboard`, `manager/assignments`, `manager/assignments/{id}/take`, `manager/assignments/{id}/close`.
- `admin/dashboard`, `admin/users`, `admin/managers/stats`, etc.

---

## Assistant IA (Mistral)

`App\Services\AiService` appelle l'endpoint compatible OpenAI de Mistral pour :
1. **Résumé de trajet** (`tripSummary`) — 3-5 phrases en français pour passager + transporteur.
2. **Statistiques par rôle** (`userStats`) — bilan en puces + recommandations (passager / transporteur / gestionnaire / admin).

Si l'IA est désactivée (`AI_ENABLED=false`) ou en échec, un **repli déterministe** génère un texte par règle (`generateur = REGLE`). La détection d'anomalies (`detectAnomalies`) est calculée par requêtes SQL (pas d'appel LLM).

---

## Vérification d'identité (Didit KYC)

Flux : le mobile envoie une photo de CNI/passeport → `IdentityController::submit()` appelle **Didit** → le résultat OCR (`ocr_data`) et le statut sont stockés.
Statuts : `EN_ATTENTE`, `VERIFIE`, `ECHOUE`, `A_EXAMINER`.
En cas de réponse Didit non conclusive (ex. crédits épuisés), le dossier passe en `A_EXAMINER` et un **gestionnaire** le revise manuellement (`identity/{id}/review`). C'est le comportement attendu en démo sans crédits.

---

## SOS vocal sécurisé

Le passager définit un **mot/phrase de sécurité** et s'enrôle (`voice/enroll`). Au déclenchement, l'alerte transmet position + détails du trajet aux **contacts d'urgence** (email réel SMTP + notification in-app FCM), au **gestionnaire**, et aux **services d'urgence** (email).

### Biométrie vocale embarquée (ECAPA-TDNN via ONNX)

Le mobile exécute un modèle d'embedding de voix **ECAPA-TDNN** (ONNX Runtime, 100 % sur l'appareil, hors-ligne et gratuit) :

1. **Enrôlement** : le passager prononce le mot de sécurité → le mobile calcule un **embedding de voix** (192 valeurs) → envoi à `voice/enroll` (stocké en JSON).
2. **Déclenchement** : le mobile recalcule l'embedding de la phrase prononcée → envoi avec le mot-clé dans `POST /sos` → le backend compare les deux embeddings par **similarité cosinus** (seuil ≥ 0.5) + correspondance du mot-clé → alerte **vérifiée** (`verification_passed=true`) ou en **vérification**.

**Modèle inclus** : `mobile/assets/models/ecapa_tdnn.onnx` (84 Mo, export ONNX du ECAPA-TDNN de SpeechBrain, licence MIT — provenance et SHA-256 dans `mobile/assets/models/README.md`). Entrée `audio` float32 `[1,N]` @16 kHz (waveform brute, Fbank incluse dans le graphe), sortie `embedding` `[1,1,192]`. Sans ce fichier, l'application **retombe automatiquement** sur la vérification mot-clé seule (reconnaissance vocale réelle `speech_to_text`), sans biométrie.

---

## Scénario de démo (soutenance)

1. **Backend** : `php artisan serve` (SMTP réel configuré).
2. **Inscription/connexion** : `POST /auth/register` puis `/auth/login` (récupérer le token).
3. **Trajet** : `POST /trips/start` → `confirm-embarquement` (QR) → `destination` → `locations` (GPS) → `end`. Vérifier le **résumé IA** (`GET /ai/trips/{trip}`).
4. **Assistant IA** : `GET /ai/summary` (stats par rôle Mistral).
5. **Identité (KYC)** : depuis le mobile, écran Identité → photo CNI → `POST /identity/submit` ; vérifier `GET /identity/status` (`A_EXAMINER` si Didit sans crédit).
6. **SOS** : `POST /sos` → consulter `storage/logs/laravel.log` pour confirmer l'email envoyé aux contacts/services.
7. **Objets perdus** : `POST /lost-items` → `GET /lost-items/{id}/chronology` (croisement passagers).
8. **Gestionnaire** : `GET /manager/dashboard`, `assignments`, `take`/`close` ; `GET /ai/anomalies`.

---

## Limitations connues (à mentionner en soutenance)

- **Didit** nécessite des **crédits** ; sans eux, la vérification retombe sur une révision manuelle (`A_EXAMINER`). La clé est valide, seul le solde manque.
- **Empreinte vocale SOS** : biométrie vocale réelle (embedding ECAPA-TDNN + similarité cosinus) une fois le modèle ONNX présent dans `mobile/assets/models/` ; sinon repli mot-clé seul.
- **Affichage cartographique** : intégré avec **OpenStreetMap** (`flutter_map`), **gratuit et sans clé**. L'affichage des tuiles dépend d'une connexion internet.
- **Temps réel** : notifications **push FCM** (Firebase) sur les appareils de l'utilisateur + polling in-app en secours (badge rafraîchi toutes les ~15 s). Le push nécessite les fichiers de config Firebase (`google-services.json` + `firebase-service-account.json`).
- **Secrets** : clés API dans `.env` (ne sont **jamais** commitées). À **renouveler après la soutenance**.

---

## Tests

Des tests automatisés couvrent l'authentification, les notifications, le flux de trajet et la **biométrie vocale** (`php artisan test` : 13 tests / 40 assertions ; `flutter analyze` : aucune erreur).

---

## Structure du dépôt

```
soutenance/
├── backend/                 # Laravel 12 (API, services IA/KYC, mail SOS)
│   ├── app/
│   │   ├── Http/Controllers/   # Trip, Sos, Identity, Ai, Manager, Admin, LostItem...
│   │   ├── Services/           # AiService (Mistral), DiditService (KYC)
│   │   ├── Mail/               # SosAlertMail
│   │   └── Models/
│   ├── config/services.php     # ai (Mistral), didit
│   ├── database/seeders/       # DemoSeeder, EmergencyDataSeeder
│   └── routes/api.php
├── mobile/                 # Flutter (écrans passager/transporteur, SOS, identité, IA)
│   └── lib/
│       ├── screens/           # home, sos_button, identity, ai, vehicles...
│       ├── services/          # api_service, sos_service, auth
│       └── main.dart
├── sync.ps1                # commit + push GitHub automatique
└── README.md
```
