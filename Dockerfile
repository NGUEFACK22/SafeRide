FROM php:8.3-cli

# Installer les extensions PHP nécessaires
RUN apt-get update && apt-get install -y \
    git unzip libpq-dev libicu-dev \
    && docker-php-ext-install pdo_pgsql intl bcmath \
    && rm -rf /var/lib/apt/lists/*

# Installer Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

WORKDIR /app/backend

# Copier composer.json UNIQUEMENT et installer sans scripts
COPY backend/composer.json ./
RUN composer install --no-dev --optimize-autoloader --no-interaction --no-scripts

# Copier tout le backend
COPY backend/ . .

# Créer les dossiers storage si absents
RUN mkdir -p storage/framework/{sessions,views,cache} storage/logs storage/app/public bootstrap/cache \
    && chmod -R 775 storage bootstrap/cache

EXPOSE 8000

# Script de démarrage: génère .env depuis les vars Render, puis migre et lance le serveur
COPY <<'STARTUP' /start.sh
#!/bin/sh
set -e

# Écrire .env depuis les variables d'environnement Render
cat > /app/backend/.env <<EOF
APP_NAME=${APP_NAME:-SafeRide}
APP_ENV=${APP_ENV:-production}
APP_DEBUG=${APP_DEBUG:-true}
APP_URL=${APP_URL}
APP_KEY=${APP_KEY}
DB_CONNECTION=${DB_CONNECTION:-pgsql}
DB_HOST=${DB_HOST}
DB_PORT=${DB_PORT:-5432}
DB_DATABASE=${DB_DATABASE:-neondb}
DB_USERNAME=${DB_USERNAME:-neondb_owner}
DB_PASSWORD=${DB_PASSWORD}
DB_SSLMODE=${DB_SSLMODE:-require}
SESSION_DRIVER=database
CACHE_STORE=database
QUEUE_CONNECTION=database
MAIL_MAILER=log
EOF

# Lancer les migrations
php artisan migrate --force --no-interaction

# Lancer le serveur
php artisan serve --host=0.0.0.0 --port=${PORT:-8000}
STARTUP

RUN chmod +x /start.sh

CMD ["/start.sh"]
