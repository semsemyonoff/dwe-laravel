#!/bin/bash

[ "$DEBUG" = "true" ] && set -x

# Substitute in php.ini values
[ -n "${PHP_MEMORY_LIMIT}" ] && sudo sed -i "s/!PHP_MEMORY_LIMIT!/${PHP_MEMORY_LIMIT}/" /usr/local/etc/php/conf.d/zz-config.ini
[ -n "${UPLOAD_MAX_FILESIZE}" ] && sudo sed -i "s/!UPLOAD_MAX_FILESIZE!/${UPLOAD_MAX_FILESIZE}/" /usr/local/etc/php/conf.d/zz-config.ini

if [ "$PHP_ENABLE_XDEBUG" = "true" ]; then
    sudo -E docker-php-ext-enable xdebug
    echo "Xdebug is enabled"
fi

echo "[$(date +'%Y-%m-%d %H:%M:%S')] Changing own and mod"
find /home/www-data -path '*/.ssh*' -prune -o -print0 | xargs -0 -P 8 -n 100 sudo chown www-data:www-data
find /home/www-data -path '*/.ssh*' -prune -o -print0 | xargs -0 -P 8 -n 100 sudo chmod g=u
if [ "$UPDATE_UID_GID" = "true" ]; then
    find /var/www/app -path '*/.git*' -prune -o -print0 | xargs -0 -P 8 -n 100 sudo chown www-data:www-data
    find /var/www/app -path '*/.git*' -prune -o -print0 | xargs -0 -P 8 -n 100 sudo chmod g=u
fi
echo "[$(date +'%Y-%m-%d %H:%M:%S')] Changed complete"

# Color prompt
# shellcheck disable=SC2028
grep -q '^PS1=' ~/.bashrc 2>/dev/null || echo "PS1='\\[\\e[1;31m\\]\\u@\\h:\\[\\e[1;34m\\]\\w\\[\\e[1;36m\\]\\[\\e[0m\\]\\$ '" >> ~/.bashrc

exec "$@"
