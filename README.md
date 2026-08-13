# SafeRide AI

Plateforme mobile intelligente de **sécurisation et de traçabilité des déplacements en taxi et moto-taxi**.

SafeRide AI met en relation passagers et transporteurs et assure :
- **Identification des personnes présentes dans un véhicule** via le scan du QR Code unique du transporteur. L'embarquement enregistre automatiquement le passager, le transporteur, le véhicule, la date, l'heure et la position GPS du scan (point de départ).
- **Saisie de la destination et suivi GPS** du trajet affiché sur une carte.
- **Déclenchement SOS vocal sécurisé** : mot/phrase de sécurité + empreinte vocale. L'alerte transmet position et détails du trajet aux contacts d'urgence, au gestionnaire et, le cas échéant, aux services d'urgence.
- **Signalement d'objets perdus** rattaché au trajet et au transporteur, avec ouverture de **litige** et reconstitution de la chronologie par croisement des passagers d'un même véhicule.
- **Vérification d'identité** (CNI / passeport) des passagers et transporteurs via une API spécialisée.
- **Intelligence artificielle** : résumés, détection d'anomalies et statistiques (vision par gestionnaire + vision globale admin).

**Stack** : backend **Laravel 12** (API + assistant IA Mistral) et application mobile **Flutter** (mode hors-ligne, service de fond Android).
