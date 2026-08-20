FROM php:8.3-cli

# Installer les extensions PHP nécessaires
RUN apt-get update && apt-get install -y \
    git unzip libpq-dev libicu-dev \
    && docker-php-ext-install pdo_pgsql intl bcmath \
    && rm -rf /var/lib/apt/lists/*

# Installer Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

WORKDIR /app

# Copier composer.json + composer.lock, installer les dépendances
COPY composer.json composer.lock ./
RUN composer install --no-dev --optimize-autoloader --no-scripts --no-interaction

# Copier le reste du code
COPY . .

# Créer les dossiers storage si absents
RUN mkdir -p storage/framework/{sessions,views,cache} storage/logs storage/app/public bootstrap/cache \
    && chmod -R 775 storage bootstrap/cache

EXPOSE 8000

# Render fournit $PORT — sh -c l'évalue au démarrage
CMD ["sh", "-c", "php artisan key:generate --force --no-interaction && php artisan migrate --force --no-interaction && php artisan serve --host=0.0.0.0 --port=${PORT:-8000}"]
