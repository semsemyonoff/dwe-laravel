FROM php:8.3-fpm

RUN apt-get update && apt-get install -y \
        libzip-dev \
        libicu-dev \
    && docker-php-ext-install pdo_mysql bcmath zip intl \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
