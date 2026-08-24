FROM php:8.3-cli

RUN apt-get update && apt-get install -y \
    git unzip libpq-dev libicu-dev \
    && docker-php-ext-install pdo_pgsql intl bcmath \
    && echo "upload_max_filesize=20M\npost_max_size=25M\nmax_file_uploads=20\nmemory_limit=256M" > /usr/local/etc/php/conf.d/uploads.ini \
    && rm -rf /var/lib/apt/lists/*

COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

WORKDIR /app/backend

COPY backend/composer.json ./
RUN composer install --no-dev --optimize-autoloader --no-interaction --no-scripts

COPY backend/ . .
COPY start.sh /start.sh
RUN chmod +x /start.sh

RUN mkdir -p storage/framework/{sessions,views,cache} storage/logs storage/app/public bootstrap/cache \
    && chmod -R 775 storage bootstrap/cache

EXPOSE 8000

CMD ["/start.sh"]
