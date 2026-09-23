ARG MAIN_IMAGE_TAG=8.5
ARG BASE_IMAGE=ghcr.io/semsemyonoff/dwe-laravel-php
FROM ${BASE_IMAGE}:${MAIN_IMAGE_TAG}

COPY misc/xdebug.ini /usr/local/etc/php/conf.d/xdebug-custom.ini

COPY misc/spx.ini /usr/local/etc/php/conf.d/zz-spx.ini

# OpenTelemetry auto-instrumentation hooks (ext-opentelemetry). Built but NOT
# enabled — same pattern as xdebug: no conf.d ini here, so PHP never loads the
# .so. The otel tool's compose_after: overlay (compose/tools/otel-apps.yml)
# mounts the ini that loads it, together with the SDK prepend.
ARG OTEL_EXT_VER=1.4.2
RUN pecl install -o -f opentelemetry-${OTEL_EXT_VER} && rm -rf /tmp/pear

ENV PHP_MEMORY_LIMIT=4G
ENV DEBUG=false

COPY docker-entrypoint.sh /docker-entrypoint.sh

RUN ["chmod", "+x", "/docker-entrypoint.sh"]

ENTRYPOINT ["/docker-entrypoint.sh"]

ENV UPLOAD_MAX_FILESIZE=64M

COPY misc/php-fpm.ini /usr/local/etc/php/conf.d/zz-config.ini
COPY misc/php-fpm.conf /usr/local/etc/

# Fix user for Linux + VSCode (chsh)
ARG UID=1000
ARG GID=1000
RUN usermod -d /home/www-data www-data \
  && usermod -u ${UID} www-data && groupmod -g ${GID} www-data \
  && usermod -aG sudo www-data \
  && echo "%sudo ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/nopasswd \
  && chsh -s /bin/bash www-data

HEALTHCHECK --interval=5s --timeout=3s --retries=50 \
    CMD ["sh", "-c", "nc -z 127.0.0.1 9000"]

USER www-data

CMD ["php-fpm", "-F"]
