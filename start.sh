#!/bin/sh
set -e
cd /app/backend

# Écrire .env avec les vars Render (injectées au runtime)
cat > .env <<ENVEOF
APP_NAME=SafeRide
APP_ENV=production
APP_DEBUG=true
APP_KEY=
APP_URL=https://saferide-api-udra.onrender.com
APP_LOCALE=en
APP_FALLBACK_LOCALE=en
APP_FAKER_LOCALE=en_US
APP_MAINTENANCE_DRIVER=file
APP_MAINTENANCE_STORE=database
DB_CONNECTION=${DB_CONNECTION}
DB_HOST=${DB_HOST}
DB_PORT=${DB_PORT}
DB_DATABASE=${DB_DATABASE}
DB_USERNAME=${DB_USERNAME}
DB_PASSWORD=${DB_PASSWORD}
DB_SSLMODE=${DB_SSLMODE}
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
MAIL_MAILER=log
GOOGLE_CLIENT_ID=${GOOGLE_CLIENT_ID}
GOOGLE_ANDROID_CLIENT_ID=${GOOGLE_ANDROID_CLIENT_ID}
INFOBIP_BASE_URL=${INFOBIP_BASE_URL}
INFOBIP_API_KEY=${INFOBIP_API_KEY}
INFOBIP_SENDER=${INFOBIP_SENDER}
AI_ENABLED=${AI_ENABLED}
AI_BASE_URL=${AI_BASE_URL}
AI_MODEL=${AI_MODEL}
ENVEOF

# Générer la clé d'encryption
php artisan key:generate --force --no-interaction

# Lancer les migrations
php artisan migrate --force --no-interaction

# Lancer le serveur
php artisan serve --host=0.0.0.0 --port=${PORT:-8000}
