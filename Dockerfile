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
CMD ["sh", "-c", "\
  printf 'APP_NAME=%s\\nAPP_ENV=%s\\nAPP_DEBUG=%s\\nAPP_URL=%s\\nAPP_KEY=%s\\n' \"$APP_NAME\" \"$APP_ENV\" \"$APP_DEBUG\" \"$APP_URL\" \"$APP_KEY\" > .env && \
  printf 'DB_CONNECTION=%s\\nDB_HOST=%s\\nDB_PORT=%s\\nDB_DATABASE=%s\\nDB_USERNAME=%s\\nDB_PASSWORD=%s\\nDB_SSLMODE=%s\\n' \"$DB_CONNECTION\" \"$DB_HOST\" \"$DB_PORT\" \"$DB_DATABASE\" \"$DB_USERNAME\" \"$DB_PASSWORD\" \"$DB_SSLMODE\" >> .env && \
  echo 'SESSION_DRIVER=database' >> .env && \
  echo 'CACHE_STORE=database' >> .env && \
  php artisan migrate --force --no-interaction && \
  php artisan serve --host=0.0.0.0 --port=${PORT:-8000}"]
