#!/bin/bash -e

source ./entrypoint_nginx.sh

# Initialize nginx
echo "INIT | Initialize NGINX ..." && init_nginx

# Configure NGINX to connect to PHP-FPM over TCP if a host is provided
if [[ -n "$PHP_FPM_HOST" ]]; then
    echo "... setting 'fastcgi_pass' to $PHP_FM_HOST:${PHP_FPM_PORT:-9000}"
    sed -i "s@fastcgi_pass .*;@fastcgi_pass $PHP_PFM_HOST:${PHP_FPM_PORT:-9000};@" /etc/nginx/includes/misp
fi

echo "INIT | Flip NGINX live ..." && flip_nginx true true

# Launch nginx as current shell process in container
exec nginx -g 'daemon off;'
