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

# Rendre le script d'entrée exécutable
RUN chmod +x docker-entrypoint.sh 2>/dev/null || true

EXPOSE 8000

# Script d'entrée: génère la clé + migrations au démarrage (pas au build)
CMD ["sh", "-c", "php artisan key:generate --force --no-interaction && php artisan migrate --force --no-interaction && php artisan serve --host=0.0.0.0 --port=8000"]
