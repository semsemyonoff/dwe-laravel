#!/bin/bash

[ "$DEBUG" = "true" ] && set -x

# Substitute in php.ini values
[ -n "${PHP_MEMORY_LIMIT}" ] && sudo sed -i "s/!PHP_MEMORY_LIMIT!/${PHP_MEMORY_LIMIT}/" /usr/local/etc/php/conf.d/zz-config.ini
[ -n "${UPLOAD_MAX_FILESIZE}" ] && sudo sed -i "s/!UPLOAD_MAX_FILESIZE!/${UPLOAD_MAX_FILESIZE}/" /usr/local/etc/php/conf.d/zz-config.ini

if [ "$PHP_ENABLE_XDEBUG" = "true" ]; then
    sudo -E docker-php-ext-enable xdebug
    echo "Xdebug is enabled"
fi

# Make the home directory (mounted volume) writable for www-data.
# /workspace/src ownership is fixed up-front by `services.main.chown-src` during
# deploy (workspace/commands/services/main.yml), so we no longer touch it here.
# `.ssh` is a read-only mount owned/locked by the host — leave it alone.
echo "[$(date +'%Y-%m-%d %H:%M:%S')] Normalising /home/www-data ownership"
find /home/www-data -path '*/.ssh*' -prune -o -print0 | xargs -0 -r -P 8 -n 100 sudo chown www-data:www-data
find /home/www-data -path '*/.ssh*' -prune -o -print0 | xargs -0 -r -P 8 -n 100 sudo chmod g=u
echo "[$(date +'%Y-%m-%d %H:%M:%S')] Done"

# Color prompt
# shellcheck disable=SC2028
grep -q '^PS1=' ~/.bashrc 2>/dev/null || echo "PS1='\\[\\e[1;31m\\]\\u@\\h:\\[\\e[1;34m\\]\\w\\[\\e[1;36m\\]\\[\\e[0m\\]\\$ '" >> ~/.bashrc

exec "$@"
