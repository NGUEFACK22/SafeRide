# --- Stage 1: Install dependencies ---
FROM composer:latest AS vendor
WORKDIR /app/backend
COPY backend/composer.json backend/composer.lock ./
RUN composer install --no-dev --optimize-autoloader --no-interaction --no-scripts

# --- Stage 2: Build ---
FROM php:8.3-cli AS build

RUN apt-get update && apt-get install -y \
    git unzip libpq-dev libicu-dev \
    && docker-php-ext-install pdo_pgsql intl bcmath \
    && echo "upload_max_filesize=20M\npost_max_size=25M\nmax_file_uploads=20\nmemory_limit=256M" > /usr/local/etc/php/conf.d/uploads.ini \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app/backend

# Copy installed dependencies from composer stage
COPY --from=vendor /app/backend/vendor ./vendor

# Copy application code
COPY backend/ .

# Create required directories
RUN mkdir -p storage/framework/{sessions,views,cache} storage/logs storage/app/public bootstrap/cache \
    && chmod -R 775 storage bootstrap/cache

# Copy entrypoint
COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 8000

CMD ["/start.sh"]
