FROM php:8.4-fpm-alpine

# -----------------------------------------------------------------------------
# System packages needed to build PHP extensions + run Laravel tooling
# -----------------------------------------------------------------------------
RUN apk add --no-cache \
        bash \
        git \
        curl \
        unzip \
        zip \
        libzip-dev \
        libpng-dev \
        libjpeg-turbo-dev \
        freetype-dev \
        postgresql-dev \
        oniguruma-dev \
        icu-dev \
        linux-headers \
        libxml2-dev \
        curl-dev \
        $PHPIZE_DEPS

# -----------------------------------------------------------------------------
# PHP extensions required by Laravel 13 + SCR platform features:
#   pdo_pgsql   -> PostgreSQL 14+ (SOW §2.3)
#   mbstring    -> multibyte string handling
#   curl        -> HTTP client (SOW §3.2)
#   dom         -> XML parsing (SOW §3.2)
#   xml         -> XML parsing (SOW §3.2)
#   redis       -> cache/session/queue driver (SOW §3.4/3.5)
#   gd          -> image handling (avatars, §3.1)
#   zip         -> manuscript ZIP ingestion (§3.3)
#   bcmath      -> precise numeric handling
#   intl        -> locale/formatting
#   opcache     -> performance
#   pcntl/sockets -> Reverb WebSocket server (§2.4)
# -----------------------------------------------------------------------------
RUN docker-php-ext-configure gd --with-jpeg --with-freetype \
    && docker-php-ext-install -j$(nproc) \
        pdo_pgsql \
        mbstring \
        curl \
        dom \
        xml \
        gd \
        zip \
        bcmath \
        intl \
        opcache \
        pcntl \
        sockets \
    && pecl install redis \
    && docker-php-ext-enable redis

# Composer (pinned via official image, always latest 2.x)
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /var/www/html

# Entrypoint handles bootstrap-if-missing, composer install, key:generate,
# waiting for postgres, and running migrations before handing off to the
# actual process (php-fpm, queue:work, or reverb:start — see docker-compose).
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Create www-data home + fix ownership so composer/npm-style installs work
# without permission errors when the bind mount is owned by the host user.
RUN mkdir -p /var/www/.composer && chown -R www-data:www-data /var/www

ENTRYPOINT ["entrypoint.sh"]
CMD ["php-fpm"]
