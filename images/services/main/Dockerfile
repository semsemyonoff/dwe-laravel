ARG MAIN_IMAGE_TAG=8.5
ARG BASE_IMAGE=semsemyonoff/devbox-laravel-php
FROM ${BASE_IMAGE}:${MAIN_IMAGE_TAG}

COPY misc/xdebug.ini /usr/local/etc/php/conf.d/xdebug-custom.ini

COPY misc/spx.ini /usr/local/etc/php/conf.d/zz-spx.ini

ENV PHP_MEMORY_LIMIT=4G
ENV DEBUG=false

COPY docker-entrypoint.sh /docker-entrypoint.sh

RUN ["chmod", "+x", "/docker-entrypoint.sh"]

ENTRYPOINT ["/docker-entrypoint.sh"]

ENV UPLOAD_MAX_FILESIZE=64M

COPY misc/php-fpm.ini /usr/local/etc/php/conf.d/zz-config.ini
COPY misc/php-fpm.conf /usr/local/etc/

# Fix user for Linux
ARG UID=1000
ARG GID=1000
RUN usermod -d /home/www-data www-data
RUN usermod -u ${UID} www-data && groupmod -g ${GID} www-data
RUN usermod -aG sudo www-data
RUN echo "%sudo ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/nopasswd
# Fix for VSCode
RUN chsh -s /bin/bash www-data

HEALTHCHECK --interval=5s --timeout=3s --retries=50 \
    CMD ["sh", "-c", "nc -z 127.0.0.1 9000"]

USER www-data

CMD ["php-fpm", "-F"]
