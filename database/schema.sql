CREATE DATABASE IF NOT EXISTS saferide
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE saferide;

-- ---------------------------------------------------------------------------
-- Identité et accès
-- ---------------------------------------------------------------------------

CREATE TABLE users (
  id               BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  nom              VARCHAR(100) NOT NULL,
  prenom           VARCHAR(100) NOT NULL,
  email            VARCHAR(190) NOT NULL,
  telephone        VARCHAR(20)  NOT NULL,
  password         VARCHAR(255) NOT NULL,
  photo_url        VARCHAR(255) NULL,
  statut           ENUM('ACTIF','SUSPENDU','DESACTIVE') NOT NULL DEFAULT 'ACTIF',
  email_verified_at TIMESTAMP NULL,
  created_at       TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at       TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_users_email (email),
  UNIQUE KEY uq_users_telephone (telephone)
) ENGINE=InnoDB;

CREATE TABLE roles (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  nom         VARCHAR(50) NOT NULL,
  slug        VARCHAR(50) NOT NULL,
  description VARCHAR(255) NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_roles_nom (nom),
  UNIQUE KEY uq_roles_slug (slug)
) ENGINE=InnoDB;

CREATE TABLE permissions (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  nom         VARCHAR(50) NOT NULL,
  slug        VARCHAR(50) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_permissions_slug (slug)
) ENGINE=InnoDB;

CREATE TABLE user_roles (
  user_id BIGINT UNSIGNED NOT NULL,
  role_id BIGINT UNSIGNED NOT NULL,
  PRIMARY KEY (user_id, role_id),
  CONSTRAINT fk_user_roles_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
  CONSTRAINT fk_user_roles_role FOREIGN KEY (role_id) REFERENCES roles (id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE role_permissions (
  role_id       BIGINT UNSIGNED NOT NULL,
  permission_id BIGINT UNSIGNED NOT NULL,
  PRIMARY KEY (role_id, permission_id),
  CONSTRAINT fk_rp_role FOREIGN KEY (role_id) REFERENCES roles (id) ON DELETE CASCADE,
  CONSTRAINT fk_rp_permission FOREIGN KEY (permission_id) REFERENCES permissions (id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------------
-- Véhicules et QR
-- ---------------------------------------------------------------------------

CREATE TABLE vehicles (
  id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  transporteur_id   BIGINT UNSIGNED NOT NULL,
  marque            VARCHAR(60)  NOT NULL,
  modele            VARCHAR(60)  NOT NULL,
  immatriculation   VARCHAR(20)  NOT NULL,
  type              ENUM('MOTO','VOITURE','MINIBUS','BUS') NOT NULL DEFAULT 'VOITURE',
  couleur           VARCHAR(30)  NULL,
  statut            ENUM('ACTIF','INACTIF') NOT NULL DEFAULT 'ACTIF',
  created_at        TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at        TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_vehicles_immatriculation (immatriculation),
  KEY idx_vehicles_transporteur (transporteur_id),
  CONSTRAINT fk_vehicles_transporteur FOREIGN KEY (transporteur_id)
    REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE qr_codes (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  vehicle_id    BIGINT UNSIGNED NOT NULL,
  token         VARCHAR(255) NOT NULL,
  actif         TINYINT(1) NOT NULL DEFAULT 1,
  expires_at    TIMESTAMP NULL,
  last_used_at  TIMESTAMP NULL,
  created_at    TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_qr_codes_token (token),
  KEY idx_qr_codes_vehicle (vehicle_id),
  CONSTRAINT fk_qr_codes_vehicle FOREIGN KEY (vehicle_id)
    REFERENCES vehicles (id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------------
-- Vérification d'identité (service externe KYC)
-- ---------------------------------------------------------------------------

CREATE TABLE identity_verifications (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id     BIGINT UNSIGNED NOT NULL,
  type        ENUM('CNI','PASSEPORT','AUTRE') NOT NULL DEFAULT 'CNI',
  statut      ENUM('EN_ATTENTE','VERIFIE','ECHOUE','A_EXAMINER') NOT NULL DEFAULT 'EN_ATTENTE',
  provider_kyc VARCHAR(100) NULL,
  verifie_le  TIMESTAMP NULL,
  created_at  TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at  TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_iv_user (user_id),
  CONSTRAINT fk_iv_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE identity_documents (
  id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id         BIGINT UNSIGNED NOT NULL,
  verification_id BIGINT UNSIGNED NULL,
  type            ENUM('CNI','PASSEPORT','AUTRE') NOT NULL DEFAULT 'CNI',
  numero          VARCHAR(100) NULL,
  fichier_url     VARCHAR(255) NOT NULL,
  ocr_data        JSON NULL,
  created_at      TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_idoc_user (user_id),
  CONSTRAINT fk_idoc_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
  CONSTRAINT fk_idoc_verification FOREIGN KEY (verification_id)
    REFERENCES identity_verifications (id) ON DELETE SET NULL
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------------
-- Sécurité passager
-- ---------------------------------------------------------------------------

CREATE TABLE emergency_contacts (
  id         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id    BIGINT UNSIGNED NOT NULL,
  nom        VARCHAR(100) NOT NULL,
  telephone  VARCHAR(20)  NOT NULL,
  relation   VARCHAR(50)  NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_ec_user (user_id),
  CONSTRAINT fk_ec_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE voice_security_profiles (
  id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id         BIGINT UNSIGNED NOT NULL,
  mot_securite    VARCHAR(255) NOT NULL,
  empreinte_vocale BLOB NULL,
  actif           TINYINT(1) NOT NULL DEFAULT 1,
  created_at      TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at      TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_vsp_user (user_id),
  CONSTRAINT fk_vsp_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------------
-- Trajets et positions GPS
-- ---------------------------------------------------------------------------

CREATE TABLE trips (
  id                    BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  passager_id           BIGINT UNSIGNED NOT NULL,
  transporteur_id       BIGINT UNSIGNED NOT NULL,
  vehicle_id            BIGINT UNSIGNED NOT NULL,
  qr_token              VARCHAR(255) NULL,
  start_latitude        DECIMAL(10,7) NOT NULL,
  start_longitude       DECIMAL(10,7) NOT NULL,
  destination_latitude  DECIMAL(10,7) NOT NULL,
  destination_longitude DECIMAL(10,7) NOT NULL,
  destination_address   VARCHAR(255) NOT NULL,
  started_at            TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  ended_at              TIMESTAMP NULL,
  distance_km           DECIMAL(8,2) NULL,
  duration_seconds      INT NULL,
  deviation_km          DECIMAL(8,2) NULL,
  statut                ENUM('EN_COURS','TERMINE','ANNULE') NOT NULL DEFAULT 'EN_COURS',
  end_method            ENUM('MANUEL','AUTO_10MIN') NULL,
  created_at            TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at            TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_trips_passager (passager_id),
  KEY idx_trips_transporteur (transporteur_id),
  KEY idx_trips_vehicle (vehicle_id),
  KEY idx_trips_statut (statut),
  CONSTRAINT fk_trips_passager FOREIGN KEY (passager_id) REFERENCES users (id) ON DELETE CASCADE,
  CONSTRAINT fk_trips_transporteur FOREIGN KEY (transporteur_id) REFERENCES users (id) ON DELETE CASCADE,
  CONSTRAINT fk_trips_vehicle FOREIGN KEY (vehicle_id) REFERENCES vehicles (id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE trip_locations (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  trip_id       BIGINT UNSIGNED NOT NULL,
  latitude      DECIMAL(10,7) NOT NULL,
  longitude     DECIMAL(10,7) NOT NULL,
  vitesse_km_h  DECIMAL(5,2) NULL,
  captured_at   TIMESTAMP NOT NULL,
  PRIMARY KEY (id),
  KEY idx_tl_trip_captured (trip_id, captured_at),
  CONSTRAINT fk_tl_trip FOREIGN KEY (trip_id) REFERENCES trips (id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------------
-- Incidents
-- ---------------------------------------------------------------------------

CREATE TABLE lost_item_reports (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  trip_id     BIGINT UNSIGNED NOT NULL,
  passager_id BIGINT UNSIGNED NOT NULL,
  objet       VARCHAR(150) NOT NULL,
  description TEXT NULL,
  statut      ENUM('SIGNALE','EN_RECHERCHE','RETROUVE','RESTITUE','NON_RETROUVE','CLOTURE')
              NOT NULL DEFAULT 'SIGNALE',
  created_at  TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at  TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_lir_trip (trip_id),
  KEY idx_lir_passager (passager_id),
  CONSTRAINT fk_lir_trip FOREIGN KEY (trip_id) REFERENCES trips (id) ON DELETE CASCADE,
  CONSTRAINT fk_lir_passager FOREIGN KEY (passager_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE disputes (
  id             BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  trip_id        BIGINT UNSIGNED NULL,
  passager_id    BIGINT UNSIGNED NOT NULL,
  transporteur_id BIGINT UNSIGNED NULL,
  motif          VARCHAR(255) NOT NULL,
  description    TEXT NULL,
  decision       TEXT NULL,
  statut         ENUM('OUVERT','EN_COURS','EN_ATTENTE','RESOLU','CLOTURE')
                 NOT NULL DEFAULT 'OUVERT',
  created_at     TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at     TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_disputes_trip (trip_id),
  KEY idx_disputes_passager (passager_id),
  CONSTRAINT fk_disputes_trip FOREIGN KEY (trip_id) REFERENCES trips (id) ON DELETE SET NULL,
  CONSTRAINT fk_disputes_passager FOREIGN KEY (passager_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------------
-- SOS
-- ---------------------------------------------------------------------------

CREATE TABLE sos_alerts (
  id               BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  trip_id          BIGINT UNSIGNED NOT NULL,
  passager_id      BIGINT UNSIGNED NOT NULL,
  declenchement    ENUM('VOCAL','BOUTON') NOT NULL,
  latitude         DECIMAL(10,7) NOT NULL,
  longitude        DECIMAL(10,7) NOT NULL,
  heure_detection  TIMESTAMP NOT NULL,
  statut           ENUM('DETECTE','VERIFICATION','DECLENCHE','NOTIFIE','EN_COURS',
                        'RESOLU','FAUSSE_ALERTE','CLOTE')
                   NOT NULL DEFAULT 'DETECTE',
  details          JSON NULL,
  created_at       TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at       TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_sos_trip (trip_id),
  KEY idx_sos_passager (passager_id),
  CONSTRAINT fk_sos_trip FOREIGN KEY (trip_id) REFERENCES trips (id) ON DELETE CASCADE,
  CONSTRAINT fk_sos_passager FOREIGN KEY (passager_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE emergency_services (
  id         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  nom        VARCHAR(100) NOT NULL,
  telephone  VARCHAR(20)  NOT NULL,
  email      VARCHAR(190) NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_es_telephone (telephone)
) ENGINE=InnoDB;

CREATE TABLE sos_emergency_notifications (
  id                   BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  sos_alert_id         BIGINT UNSIGNED NOT NULL,
  emergency_service_id BIGINT UNSIGNED NOT NULL,
  notifie_le           TIMESTAMP NOT NULL,
  statut               ENUM('EN_ATTENTE','TRANSMISE','CONFIRMEE','ECHEC')
                       NOT NULL DEFAULT 'EN_ATTENTE',
  PRIMARY KEY (id),
  KEY idx_sen_alert (sos_alert_id),
  CONSTRAINT fk_sen_alert FOREIGN KEY (sos_alert_id) REFERENCES sos_alerts (id) ON DELETE CASCADE,
  CONSTRAINT fk_sen_service FOREIGN KEY (emergency_service_id)
    REFERENCES emergency_services (id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------------
-- Gestionnaires
-- ---------------------------------------------------------------------------

CREATE TABLE manager_assignments (
  id           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  manager_id   BIGINT UNSIGNED NOT NULL,
  dossier_type ENUM('OBJET_PERDU','LITIGE','SOS','IDENTITE') NOT NULL,
  dossier_id   BIGINT UNSIGNED NOT NULL,
  statut       ENUM('ATTRIBUE','PRIS_EN_CHARGE','CLOTURE') NOT NULL DEFAULT 'ATTRIBUE',
  assigned_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  taken_at     TIMESTAMP NULL,
  closed_at    TIMESTAMP NULL,
  PRIMARY KEY (id),
  KEY idx_ma_manager (manager_id),
  KEY idx_ma_dossier (dossier_type, dossier_id),
  CONSTRAINT fk_ma_manager FOREIGN KEY (manager_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------------
-- Notifications et audit
-- ---------------------------------------------------------------------------

CREATE TABLE notifications (
  id         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id    BIGINT UNSIGNED NOT NULL,
  type       ENUM('SOS','TRAJET','DOSSIER','IDENTITE','SYSTEME') NOT NULL DEFAULT 'SYSTEME',
  titre      VARCHAR(190) NOT NULL,
  message    TEXT NULL,
  lu         TINYINT(1) NOT NULL DEFAULT 0,
  read_at    TIMESTAMP NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_notifications_user (user_id),
  CONSTRAINT fk_notifications_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE audit_logs (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id     BIGINT UNSIGNED NULL,
  action      VARCHAR(100) NOT NULL,
  entity_type VARCHAR(60)  NULL,
  entity_id   BIGINT UNSIGNED NULL,
  details     JSON NULL,
  ip          VARCHAR(45)  NULL,
  user_agent  VARCHAR(255) NULL,
  created_at  TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_audit_user (user_id),
  KEY idx_audit_entity (entity_type, entity_id),
  CONSTRAINT fk_audit_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE SET NULL
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------------
-- IA SafeRide (service externe)
-- ---------------------------------------------------------------------------

CREATE TABLE ai_reports (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  type        ENUM('RESUME_TRAJET','STATISTIQUES','ANOMALIE','RECOMMANDATION') NOT NULL,
  contenu     TEXT NOT NULL,
  user_id     BIGINT UNSIGNED NULL,
  trip_id     BIGINT UNSIGNED NULL,
  generateur  VARCHAR(100) NOT NULL DEFAULT 'IA_SafeRide',
  created_at  TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_ai_reports_user (user_id),
  KEY idx_ai_reports_trip (trip_id),
  CONSTRAINT fk_ai_reports_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE SET NULL,
  CONSTRAINT fk_ai_reports_trip FOREIGN KEY (trip_id) REFERENCES trips (id) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE ai_insights (
  id           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  ai_report_id BIGINT UNSIGNED NOT NULL,
  titre        VARCHAR(190) NOT NULL,
  description  TEXT NULL,
  gravite      ENUM('INFO','MOYENNE','ELEVEE') NOT NULL DEFAULT 'INFO',
  created_at   TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_ai_insights_report (ai_report_id),
  CONSTRAINT fk_ai_insights_report FOREIGN KEY (ai_report_id)
    REFERENCES ai_reports (id) ON DELETE CASCADE
) ENGINE=InnoDB;