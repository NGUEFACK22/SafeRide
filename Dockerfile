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

# Créer un .env VIDE (les vars Render écrasent tout au démarrage)
RUN touch .env

# Créer les dossiers storage si absents
RUN mkdir -p storage/framework/{sessions,views,cache} storage/logs storage/app/public bootstrap/cache \
    && chmod -R 775 storage bootstrap/cache

EXPOSE 8000

CMD ["sh", "-c", "php artisan key:generate --force --no-interaction && php artisan migrate --force --no-interaction && php artisan serve --host=0.0.0.0 --port=${PORT:-8000}"]
