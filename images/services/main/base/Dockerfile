FROM alpine AS unpack
WORKDIR /unpack
ARG COMPOSER_VER=2.10.1
RUN wget https://getcomposer.org/download/${COMPOSER_VER}/composer.phar -O composer

FROM php:8.5-fpm

# System dependencies (libraries needed by the PHP extensions below + dev tools)
RUN apt-get update \
  && apt-get install -y \
    libzip-dev \
    libpng-dev \
    libjpeg-dev \
    libfreetype6-dev \
    libonig-dev \
    libxml2-dev \
    libicu-dev \
    libxslt1-dev \
    libssl-dev \
    libcurl4-openssl-dev \
    zlib1g-dev \
    libedit-dev \
    libsqlite3-dev \
    libargon2-dev \
    sudo \
    unzip \
    git \
    netcat-openbsd \
    vim \
    jq \
    procps \
    locales \
    && sed -i 's/# *\(ru_RU.UTF-8\)/\1/' /etc/locale.gen && locale-gen \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# PHP extensions (configure gd with freetype + jpeg before building).
# Not installed here, on purpose:
#   - curl / dom / simplexml / xmlwriter — enabled by default in the official image;
#   - opcache — statically built into PHP 8.5 (no shared module to build/enable),
#     turn it on via php.ini `opcache.enable=1` in the service layer.
# Installing any of the above breaks with "cp: cannot stat 'modules/*'".
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
  && docker-php-ext-install -j"$(nproc)" \
    bcmath \
    exif \
    gd \
    intl \
    mbstring \
    pcntl \
    pdo_mysql \
    soap \
    sockets \
    xsl \
    zip

# phpredis client — kept pre-installed so adding a Redis service back later
# (cache/queue/session) needs no base-image rebuild. No Redis container ships
# with the pilot by default.
RUN pecl install redis && docker-php-ext-enable redis

# Composer
ENV COMPOSER_ALLOW_SUPERUSER=1
VOLUME /root/.composer/cache
COPY --from=unpack /unpack/composer /usr/local/bin/composer
RUN chmod +x /usr/local/bin/composer

# Xdebug (installed but not enabled — toggled at runtime via PHP_ENABLE_XDEBUG)
ARG XDEBUG_VER=3.5.1
RUN pecl install -o -f xdebug-${XDEBUG_VER}
ENV PHP_ENABLE_XDEBUG=false

# PHP SPX profiler (built from source, web UI exposed via SPX_KEY)
ARG SPX_VER=0.4.22
RUN cd /usr/lib && git clone --depth 1 --branch v${SPX_VER} https://github.com/NoiseByNorthwest/php-spx.git
RUN cd /usr/lib/php-spx && phpize && ./configure && make && make install
