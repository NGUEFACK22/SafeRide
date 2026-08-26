#!/bin/sh
set -e
cd /app/backend

# Écrire .env avec les vars Render (injectées au runtime) — tous les services SafeRide
cat > .env <<ENVEOF
APP_NAME=SafeRide
APP_ENV=${APP_ENV:-production}
APP_DEBUG=${APP_DEBUG:-false}
APP_KEY=${APP_KEY:-}
APP_URL=${APP_URL:-https://saferide-api-udra.onrender.com}
APP_LOCALE=en
APP_FALLBACK_LOCALE=en
APP_FAKER_LOCALE=en_US
APP_MAINTENANCE_DRIVER=file
APP_MAINTENANCE_STORE=database
DB_CONNECTION=${DB_CONNECTION:-pgsql}
DB_HOST=${DB_HOST}
DB_PORT=${DB_PORT:-5432}
DB_DATABASE=${DB_DATABASE:-neondb}
DB_USERNAME=${DB_USERNAME}
DB_PASSWORD=${DB_PASSWORD}
DB_SSLMODE=${DB_SSLMODE:-require}
DB_NEON_ENDPOINT=${DB_NEON_ENDPOINT:-}
SESSION_DRIVER=database
SESSION_LIFETIME=120
SESSION_ENCRYPT=false
SESSION_PATH=/
SESSION_DOMAIN=null
SESSION_SECURE_COOKIE=false
CACHE_STORE=database
QUEUE_CONNECTION=database
BROADCAST_CONNECTION=log
FILESYSTEM_DISK=local
MAIL_MAILER=${MAIL_MAILER:-log}
MAIL_HOST=${MAIL_HOST:-}
MAIL_PORT=${MAIL_PORT:-587}
MAIL_USERNAME=${MAIL_USERNAME:-}
MAIL_PASSWORD=${MAIL_PASSWORD:-}
MAIL_ENCRYPTION=${MAIL_ENCRYPTION:-tls}
MAIL_FROM_ADDRESS=${MAIL_FROM_ADDRESS:-}
MAIL_FROM_NAME=${MAIL_FROM_NAME:-SafeRide}
GOOGLE_CLIENT_ID=${GOOGLE_CLIENT_ID}
GOOGLE_ANDROID_CLIENT_ID=${GOOGLE_ANDROID_CLIENT_ID}
INFOBIP_BASE_URL=${INFOBIP_BASE_URL:-https://api.infobip.com}
INFOBIP_API_KEY=${INFOBIP_API_KEY}
INFOBIP_SENDER=${INFOBIP_SENDER:-SafeRide}
INFOBIP_WHATSAPP_SENDER=${INFOBIP_WHATSAPP_SENDER:-}
AI_ENABLED=${AI_ENABLED:-false}
AI_BASE_URL=${AI_BASE_URL:-https://api.mistral.ai/v1}
AI_API_KEY=${AI_API_KEY:-}
AI_MODEL=${AI_MODEL:-mistral-small-latest}
AI_TIMEOUT=${AI_TIMEOUT:-20}
DIDIT_API_KEY=${DIDIT_API_KEY:-}
DIDIT_BASE_URL=${DIDIT_BASE_URL:-https://verification.didit.me/v3}
ENVEOF

# Générer la clé d'encryption
php artisan key:generate --force --no-interaction

# Lancer les migrations
php artisan migrate --force --no-interaction

# Optimiser pour la production
cache_flags=""
if [ "$APP_ENV" = "production" ]; then
  php artisan config:cache --no-interaction
  php artisan route:cache --no-interaction
  php artisan view:cache --no-interaction 2>/dev/null || true
fi

# Lancer le serveur
php artisan serve --host=0.0.0.0 --port=${PORT:-8000}
