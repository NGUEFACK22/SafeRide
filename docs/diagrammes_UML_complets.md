# SafeRide AI — Les 9 diagrammes UML principaux

Diagrammes couverts :
1. Diagramme de cas d'utilisation
2. Diagramme de classes
3. Diagramme d'objets
4. Diagramme de séquence
5. Diagramme de communication
6. Diagramme d'états (state chart)
7. Diagramme d'activité
8. Diagramme de composants
9. Diagramme de déploiement

> Note : Mermaid ne possède pas de formes natives « cas d'utilisation », « objets » et « communication ».
> Ils sont donc représentés de façon fidèle avec des variantes proches (graph/class). Ils sont prêts à être
> retranscrits tels quels dans StarUML, draw.io ou PlantUML pour la version soutenance.

---

## 1. Diagramme de cas d'utilisation

```mermaid
flowchart LR
  P[Passager]
  T[Transporteur]
  G[Gestionnaire]
  A[Administrateur]
  SYS[SafeRide AI]

  U1[S'inscrire]
  U2[Se connecter]
  U3["Vérifier son identité (CNI / passeport)"]
  U4[Configurer mot de sécurité + voix]
  U5[Gérer contacts d'urgence]
  U6[Scanner le QR d'embarquement]
  U7[Saisir et confirmer la destination]
  U8[Déclencher SOS bouton ou vocal]
  U9[Mettre fin au trajet]
  U10[Consulter historique et résumé IA]
  U11[Déclarer un objet perdu]
  U12[Ouvrir un litige]
  U13[Gérer véhicules et QR codes]
  U14[Être notifié d'un embarquement]
  U15[Traiter les dossiers attribués]
  U16[Examiner les identités en attente]
  U17[Gérer comptes et permissions]
  U18[Consulter les statistiques globales]

  P --- U1
  P --- U2
  P --- U3
  P --- U4
  P --- U5
  P --- U6
  P --- U7
  P --- U8
  P --- U9
  P --- U10
  P --- U11
  P --- U12

  T --- U2
  T --- U13
  T --- U14

  G --- U2
  G --- U15
  G --- U16

  A --- U2
  A --- U16
  A --- U17
  A --- U18

  U3 ..-> KYC[API KYC externe]
  U10 ..-> IA1[IA SafeRide]
  U8 ..-> URG[Services d'urgence externes]
```

Acteurs : `Passager`, `Transporteur`, `Gestionnaire`, `Administrateur` + systèmes externes (`API KYC`, `IA SafeRide`, `Services d'urgence`).

---

## 2. Diagramme de classes

```mermaid
classDiagram
  class User {
    +int id
    +string nom
    +string prenom
    +string email
    +string telephone
    +string password
    +string photo_url
    +enum statut : ACTIF|SUSPENDU|DESACTIVE
  }
  class Role {
    +int id
    +string nom
    +string slug
  }
  class Permission {
    +int id
    +string nom
    +string slug
  }
  class Vehicle {
    +int id
    +string marque
    +string modele
    +string immatriculation
    +enum type : MOTO|VOITURE|MINIBUS|BUS
    +enum statut : ACTIF|INACTIF
  }
  class QrCode {
    +int id
    +string token
    +bool actif
    +datetime expires_at
    +datetime last_used_at
  }
  class IdentityVerification {
    +int id
    +enum type : CNI|PASSEPORT|AUTRE
    +enum statut : EN_ATTENTE|VERIFIE|ECHOUE|A_EXAMINER
    +string provider_kyc
    +datetime verifie_le
  }
  class IdentityDocument {
    +int id
    +enum type : CNI|PASSEPORT|AUTRE
    +string numero
    +string fichier_url
    +json ocr_data
  }
  class EmergencyContact {
    +int id
    +string nom
    +string telephone
    +string relation
  }
  class VoiceSecurityProfile {
    +int id
    +string mot_securite
    +blob empreinte_vocale
    +bool actif
  }
  class Trip {
    +int id
    +decimal start_latitude
    +decimal start_longitude
    +decimal destination_latitude
    +decimal destination_longitude
    +string destination_address
    +datetime started_at
    +datetime ended_at
    +decimal distance_km
    +int duration_seconds
    +decimal deviation_km
    +enum statut : EN_COURS|TERMINE|ANNULE
    +enum end_method : MANUEL|AUTO_10MIN
  }
  class TripLocation {
    +int id
    +decimal latitude
    +decimal longitude
    +decimal vitesse_km_h
    +datetime captured_at
  }
  class LostItemReport {
    +int id
    +string objet
    +string description
    +enum statut : SIGNALE|EN_RECHERCHE|RETROUVE|RESTITUE|NON_RETROUVE|CLOTURE
  }
  class Dispute {
    +int id
    +string motif
    +string description
    +string decision
    +enum statut : OUVERT|EN_COURS|EN_ATTENTE|RESOLU|CLOTURE
  }
  class SosAlert {
    +int id
    +enum declenchement : VOCAL|BOUTON
    +decimal latitude
    +decimal longitude
    +datetime heure_detection
    +enum statut : DETECTE|VERIFICATION|DECLENCHE|NOTIFIE|EN_COURS|RESOLU|FAUSSE_ALERTE|CLOTE
    +json details
  }
  class EmergencyService {
    +int id
    +string nom
    +string telephone
  }
  class SosEmergencyNotification {
    +int id
    +datetime notifie_le
    +enum statut : EN_ATTENTE|TRANSMISE|CONFIRMEE|ECHEC
  }
  class ManagerAssignment {
    +int id
    +enum dossier_type : OBJET_PERDU|LITIGE|SOS|IDENTITE
    +int dossier_id
    +enum statut : ATTRIBUE|PRIS_EN_CHARGE|CLOTURE
    +datetime assigned_at
    +datetime taken_at
    +datetime closed_at
  }
  class Notification {
    +int id
    +enum type : SOS|TRAJET|DOSSIER|IDENTITE|SYSTEME
    +string titre
    +string message
    +bool lu
  }
  class AuditLog {
    +int id
    +string action
    +string entity_type
    +int entity_id
    +json details
    +string ip
    +string user_agent
  }
  class AiReport {
    +int id
    +enum type : RESUME_TRAJET|STATISTIQUES|ANOMALIE|RECOMMANDATION
    +text contenu
    +string generateur
  }
  class AiInsight {
    +int id
    +string titre
    +string description
    +enum gravite : INFO|MOYENNE|ELEVEE
  }

  User "1" --> "*" Role : user_roles
  Role "*" --> "*" Permission : role_permissions
  User "1" --> "*" Vehicle : transporte
  User "1" --> "0..1" VoiceSecurityProfile
  User "1" --> "*" EmergencyContact
  User "1" --> "*" IdentityVerification
  User "1" --> "*" IdentityDocument
  IdentityVerification "1" --> "0..1" IdentityDocument : appuye
  Vehicle "1" --> "0..*" QrCode
  Vehicle "1" --> "1" User : transporteur
  User "1" --> "*" Trip : passager
  User "1" --> "*" Trip : transporteur
  Vehicle "1" --> "*" Trip
  Trip "1" --> "*" TripLocation : itineraire reel
  Trip "1" --> "0..*" LostItemReport
  Trip "1" --> "0..*" Dispute
  Trip "1" --> "0..*" SosAlert
  User "1" --> "*" SosAlert : passager
  SosAlert "1" --> "*" SosEmergencyNotification
  EmergencyService "1" --> "*" SosEmergencyNotification
  User "1" --> "*" ManagerAssignment : gestionnaire
  User "1" --> "*" Notification
  User "1" --> "*" AuditLog
  AiReport "1" --> "*" AiInsight
  Trip "0..1" --> "0..*" AiReport
  User "0..1" --> "0..*" AiReport
```

---

## 3. Diagramme d'objets (instanciation)

Instances à un instant donné : le trajet T-1045 est EN_COURS, surveillé vocalement.

```mermaid
classDiagram
  class karim {
    nom = "Karim N'Diaye"
    telephone = "691 00 00 01"
    statut = ACTIF
    role = PASSAGER
  }
  class jean {
    nom = "Jean Dupont"
    telephone = "691 00 00 02"
    statut = ACTIF
    role = TRANSPORTEUR
  }
  class corolla {
    marque = "Toyota"
    modele = "Corolla"
    immatriculation = "LT 450 AB"
    type = VOITURE
    statut = ACTIF
  }
  class qr1 {
    token = "eyJhbGciOiJIUzI1NiIs..."
    actif = true
  }
  class trip1045 {
    statut = EN_COURS
    end_method = null
    destination_address = "Centre ville - Avenue Kennedy"
    start_latitude = 3.86670
    start_longitude = 11.51670
    deviation_km = 0.4
  }
  class loc1 {
    latitude = 3.87210
    longitude = 11.52130
    vitesse_km_h = 32.0
    captured_at = "12:04:11"
  }
  class vsp_karim {
    mot_securite = "Pendant la conduite"
    actif = true
  }

  karim --> trip1045 : a embarqué dans
  jean --> corolla : conduit
  corolla --> qr1 : porte le QR
  qr1 --> trip1045 : a déclenché
  trip1045 --> loc1 : passe par (itinéraire réel)
  karim --> vsp_karim : possède
```

---

## 4. Diagramme de séquence — Trajet complet (scénario principal)

```mermaid
sequenceDiagram
  autonumber
  actor P as Passager
  participant App as App Flutter
  participant BE as Backend Laravel
  participant GPS as Service GPS
  participant IA as IA SafeRide

  P->>App: Scan le QR du transporteur
  App->>BE: POST /trips/start (token QR + position GPS)
  BE->>BE: Valider token signé + compte actif + proximité
  alt QR invalide, expiré ou compte suspendu
    BE-->>App: Trajet refusé
    App-->>P: « Vous n'êtes pas enregistré »
  else QR validé
    BE-->>App: Trajet EN_COURS (départ GPS enregistré)
    App-->>P: « Vous êtes enregistré dans le véhicule de Jean Dupont »
    P->>App: Saisit la destination
    App-->>P: « Votre destination est-elle correcte ? (Modifier | Confirmer) »
    P->>App: Confirmer
    App->>BE: POST /trips/{id}/destination (adresse + coordonnées)
    Note over App,GPS: Démarrage de l'écoute vocale (service d'avant-plan)
    loop Trajet en cours
      GPS->>App: Position GPS (vitesse horodatée)
      App->>BE: POST /trip-locations (itinéraire réel)
      App->>App: Écoute mot de sécurité + vérification de la voix
    end
    Note over App,GPS: Arrivée à destination
    App-->>P: « Vous êtes arrivé : cliquer sur Fin de trajet »
    alt Passager clique « Fin de trajet »
      P->>App: Fin de trajet
    else 10 minutes sans action
      BE-->>App: Fin de trajet automatique
    end
    App->>BE: POST /trips/{id}/end
    BE->>BE: Calcul distance, durée, écart prévu vs réel
    BE-->>App: Récapitulatif du trajet
    BE->>IA: Analyse du trajet
    IA-->>BE: Résumé + statistiques + anomalies éventuelles
    BE-->>BE: Archivage historique + audit_logs
  end
```

## Diagramme de séquence — Déclenchement SOS (scénario secondaire)

```mermaid
sequenceDiagram
  autonumber
  participant App as App Flutter (service d'avant-plan)
  participant BE as Backend Laravel
  participant SI as IA SafeRide
  actor C as Contacts
  actor G as Gestionnaire
  actor U as Services d'urgence

  Note over App: Condition : trajet EN_COURS + écoute active
  alt Mot de sécurité reconnu ET voix du propriétaire validée
    App->>BE: POST /sos (trajet, position, preuve)
    BE->>SI: Vérifier conditions de sécurité
    SI-->>BE: Conditions satisfaites
    BE->>BE: Création SosAlert (DETECTE → DECLENCHE)
    BE->>C: Notification SOS (contacts d'urgence)
    BE->>G: Notification SOS (gestionnaire)
    BE->>U: Notification SOS (services d'urgence)
    App-->>P: « Alerte transmise »
  else Voix invalide
    App-->>P: Poursuite normale du trajet
  end
  alt Bouton SOS pressé (secours)
    P->>App: Appui long sur le bouton SOS
    App->>BE: POST /sos (bouton)
    Note over App,BE: Même traitement que le déclenchement vocal
  end
  Note over BE: Sans connexion : statut EN_ATTENTE + affichage « En attente de connexion » (jamais « Alerte transmise »)
```

---

## 5. Diagramme de communication — Démarrage d'un trajet

Mêmes échanges que la séquence, numérotés dans l'ordre.

```mermaid
flowchart TD
  subgraph Acteurs
    PASS[Passager]
  end
  subgraph Client
    APP[App Flutter]
  end
  subgraph Serveur
    BE[Backend Laravel]
  end

  PASS -- "1. scanQR()" --> APP
  APP -- "2 : POST /trips/start" --> BE
  BE -- "3 : valider(token, proximite, compte)" --> BE
  BE -- "4 : Trip EN_COURS + resumé" --> APP
  APP -- "5 : confirmerDestination()" --> BE
  BE -- "6 : destinations + depart enregistrés" --> APP
  APP -- "7 : positions(trip_locations)" --> BE
  BE -- "8 : récap + analyse IA (asynchrone)" --> APP
```

---

## 6. Diagramme d'états

### État du trajet (Trip)

```mermaid
stateDiagram-v2
  [*] --> EN_COURS : Scan QR validé
  EN_COURS --> DESTINATION_CONFIRMEE : Destination confirmée
  DESTINATION_CONFIRMEE --> SUIVI : Écoute vocale + GPS démarrés
  SUIVI --> ARRIVEE : Destination atteinte
  ARRIVEE --> TERMINE : « Fin de trajet » cliqué (MANUEL)
  ARRIVEE --> TERMINE : 10 min sans action (AUTO_10MIN)
  EN_COURS --> ANNULE : QR invalide / abandon passager
  SUIVI --> ANNULE : Trajet annulé pour incident
  TERMINE --> [*]
  ANNULE --> [*]
```

### État d'une alerte SOS (SosAlert)

```mermaid
stateDiagram-v2
  [*] --> DETECTE : Mot + voix reconnus (ou bouton)
  DETECTE --> VERIFICATION : Contrôle des conditions
  VERIFICATION --> DECLENCHE : Conditions satisfaites
  DECLENCHE --> NOTIFIE : Contacts + gestionnaire + urgences
  NOTIFIE --> EN_COURS : Traitement en cours
  EN_COURS --> RESOLU : Incident traité
  EN_COURS --> FAUSSE_ALERTE : Aucun danger confirmé
  RESOLU --> CLOTE
  FAUSSE_ALERTE --> CLOTE
  CLOTE --> [*]
```

---

## 7. Diagramme d'activité — Trajet avec surveillance vocale

Couloirs : Passager / App / Backend / Services externes.

```mermaid
flowchart TB
  subgraph PASS[Passager]
    A1[Scanne le QR] --> A2[Saisit et confirme la destination]
    A2 --> A3[Clic « Fin de trajet »]
    A3 --> A4[Consulte le récapitulatif]
  end

  subgraph APP[App Flutter]
    B1[Vérifie le QR et la position] --> B2[Lance le service d'avant-plan]
    B2 --> B3[Collecte GPS trip_locations]
    B3 --> B4[Écoute le mot de sécurité et vérifie la voix]
    B4 --> B5[Filtre SOS ou continue]
    B5 --> B2
    B2 --> B6[Fin du trajet : envoi de /end]
  end

  subgraph BE[Backend Laravel]
    C1[Valide le token : signé + actif + proximité]
    C1 --> C2[Crée le Trip EN_COURS et enregistre le départ]
    C2 --> C3[Reçoit la destination confirmée]
    C3 --> C4[Enregistre les positions + écart prévu vs réel]
    C4 --> C5[Clôture : distance, durée, end_method]
    C5 --> C6[Audit + notifications]
  end

  subgraph EXT[Services externes]
    D1[API KYC] 
    D2[IA SafeRide : résumé et anomalies]
    D3[Services d'urgence]
  end

  A1 --> B1
  B1 --> C1
  C2 --> A2
  A2 --> C3
  C3 --> B2
  B4 --> C4
  A3 --> B6
  B6 --> C5
  C5 --> D2
  C5 --> C6
  D2 --> A4
  B4 -->|Bouton SOS en secours| D3
  C4 -.cas identité en attente.-> D1
```

---

## 8. Diagramme de composants

```mermaid
flowchart TB
  subgraph CLIENT[Application Flutter]
    UI[UI composants Flutter]
    SCAN[Module Scanner QR]
    GPSM[Module Géolocalisation]
    VOICE[Module Mot de sécurité + voix]
    CACHE[Couches locaux : cache hors-ligne]
  end

  subgraph API[Backend Laravel]
    AUTH[Composant Auth - rôles - permissions]
    TRIPS[Composant Trips et positions]
    SOSC[Composant SOS]
    DOSSIERS[Composant Dossiers : litiges, objets perdus, gestionnaires]
    NOTIFC[Composant Notifications]
    AUDIT[Composant Audit]
    QUEUE[File de travaux asynchrone]
  end

  subgraph DATA[Persistance]
    DB[(MySQL)]
  end

  subgraph EXT[Services externes]
    KYC[API Identité : CNI, OCR, reconnaissance faciale]
    IA[IA SafeRide : résumés, stats, anomalies]
    PUSH[Push FCM]
    MAPS[Cartographie et itinéraire]
  end

  UI --> SCAN
  UI --> GPSM
  UI --> VOICE
  UI --> CACHE
  SCAN -- HTTP JSON --> TRIPS
  GPSM -- HTTP JSON --> TRIPS
  VOICE -- HTTP JSON --> SOSC
  UI -- HTTPS JSON --> AUTH
  UI -- HTTPS JSON --> DOSSIERS
  AUTH --> NOTIFC
  TRIPS --> NOTIFC
  SOSC --> NOTIFC
  DOSSIERS --> NOTIFC
  NOTIFC --> DB
  TRIPS --> DB
  SOSC --> DB
  DOSSIERS --> DB
  AUDIT --> DB
  QUEUE --> NOTIFC
  QUEUE --> KYC
  QUEUE --> IA
  NOTIFC -- REST --> PUSH
  TRIPS -- REST --> MAPS
  SOSC -- REST --> MAPS
```

---

## 9. Diagramme de déploiement

```mermaid
flowchart TB
  subgraph MOBILE[Noeud : Téléphone de l'utilisateur]
    APP[App Flutter - Android]
    STORAGE[Stockage local : cache GPS, alerte SOS en attente]
  end

  subgraph SERVEUR_APP[Noeud : Serveur applicatif]
    NGINX[Conteneur Nginx]
    PHP[Conteneur PHP-FPM : Laravel API]
    QUEUE[Conteneur worker files]
  end

  subgraph SERVEUR_DB[Noeud : Serveur base de données]
    MYSQL[(MySQL 8)]
  end

  subgraph CLOUD[Provisions externes]
    KC[API KYC]
    SR[IA SafeRide]
    FCM[Notifications FCM]
    MC[Cartographie]
  end

  APP -- HTTPS 443 --> NGINX
  APP --> STORAGE
  NGINX --> PHP
  PHP --> MYSQL : MySQL 3306
  PHP --> QUEUE
  QUEUE -- REST --> KC
  QUEUE -- REST --> SR
  PHP -- REST --> FCM
  APP -- REST --> MC
  PHP -- REST --> MC
```