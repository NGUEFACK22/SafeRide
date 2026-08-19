FROM php:8.3-cli

# Installer les extensions PHP nécessaires
RUN apt-get update && apt-get install -y \
    git unzip libpq-dev libicu-dev \
    && docker-php-ext-install pdo_pgsql intl bcmath \
    && rm -rf /var/lib/apt/lists/*

# Installer Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

WORKDIR /app

# Copier composer.json et installer les dépendances
COPY composer.json composer.lock ./
RUN composer install --no-dev --optimize-autoloader --no-scripts

# Copier le reste du code
COPY . .

# Générer la clé et préparer l'app
RUN php artisan key:generate --force \
    && php artisan config:cache \
    && php artisan route:cache

EXPOSE 8000

CMD php artisan serve --host=0.0.0.0 --port=8000
