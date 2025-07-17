#!/bin/sh

init_nginx() {
    # Optional location of PHP-FPM sock file
    if [ -n "$PHP_FPM_HOST" ]; then
        echo "... setting 'fastcgi_pass' to $PHP_FPM_HOST:${PHP_FPM_PORT:-9000}"
        sed -i "s@fastcgi_pass .*;@fastcgi_pass $PHP_FPM_HOST:${PHP_FPM_PORT:-9000};@" /etc/nginx/includes/misp
    fi
    elif [ -n "$PHP_FPM_SOCK_FILE" ]; then
        echo "... setting 'fastcgi_pass' to unix:${PHP_FPM_SOCK_FILE}"
        sed -i "s@fastcgi_pass .*;@fastcgi_pass unix:${PHP_FPM_SOCK_FILE};@" /etc/nginx/includes/misp
    fi

    # Adjust timeouts
    echo "... adjusting 'fastcgi_read_timeout' to ${FASTCGI_READ_TIMEOUT}"
    sed -i "s/fastcgi_read_timeout .*;/fastcgi_read_timeout ${FASTCGI_READ_TIMEOUT};/" /etc/nginx/includes/misp
    echo "... adjusting 'fastcgi_send_timeout' to ${FASTCGI_SEND_TIMEOUT}"
    sed -i "s/fastcgi_send_timeout .*;/fastcgi_send_timeout ${FASTCGI_SEND_TIMEOUT};/" /etc/nginx/includes/misp
    echo "... adjusting 'fastcgi_connect_timeout' to ${FASTCGI_CONNECT_TIMEOUT}"
    sed -i "s/fastcgi_connect_timeout .*;/fastcgi_connect_timeout ${FASTCGI_CONNECT_TIMEOUT};/" /etc/nginx/includes/misp

    echo "... adjusting 'client_max_body_size' to ${NGINX_CLIENT_MAX_BODY_SIZE}"
    sed -i "s/client_max_body_size .*;/client_max_body_size ${NGINX_CLIENT_MAX_BODY_SIZE};/" /etc/nginx/includes/misp

    sed -i '/real_ip_header/d' /etc/nginx/includes/misp
    sed -i '/real_ip_recursive/d' /etc/nginx/includes/misp
    sed -i '/set_real_ip_from/d' /etc/nginx/includes/misp

    if [ "$NGINX_X_FORWARDED_FOR" = "true" ]; then
        echo "... enabling X-Forwarded-For header"
        sed -i "/index index.php/a real_ip_header X-Forwarded-For;\nreal_ip_recursive on;" /etc/nginx/includes/misp

        if [ -n "$NGINX_SET_REAL_IP_FROM" ]; then
            echo "$NGINX_SET_REAL_IP_FROM" | tr ',' '\n' | while read real_ip; do
                echo "... setting 'set_real_ip_from ${real_ip}'"
                sed -i "/real_ip_recursive on/a set_real_ip_from ${real_ip};" /etc/nginx/includes/misp
            done
        fi
    fi

    echo "... adjusting Content-Security-Policy"
    sed -i '/add_header Content-Security-Policy/d' /etc/nginx/includes/misp

    if [ -n "$CONTENT_SECURITY_POLICY" ]; then
        echo "... setting Content-Security-Policy to '$CONTENT_SECURITY_POLICY'"
        sed -i "/add_header X-Download-Options/a add_header Content-Security-Policy \"$CONTENT_SECURITY_POLICY\";" /etc/nginx/includes/misp
    else
        echo "... no Content-Security-Policy header will be set as CONTENT_SECURITY_POLICY is not defined"
    fi

    echo "... adjusting X-Frame-Options"
    sed -i '/add_header X-Frame-Options/d' /etc/nginx/includes/misp

    if [ -z "$X_FRAME_OPTIONS" ]; then
        echo "... setting 'X-Frame-Options SAMEORIGIN'"
        sed -i "/add_header X-Download-Options/a add_header X-Frame-Options \"SAMEORIGIN\" always;" /etc/nginx/includes/misp
    else
        echo "... setting 'X-Frame-Options $X_FRAME_OPTIONS'"
        sed -i "/add_header X-Download-Options/a add_header X-Frame-Options \"$X_FRAME_OPTIONS\";" /etc/nginx/includes/misp
    fi

    echo "... adjusting HTTP Strict Transport Security (HSTS)"
    sed -i '/add_header Strict-Transport-Security/d' /etc/nginx/includes/misp

    if [ -n "$HSTS_MAX_AGE" ]; then
        echo "... setting HSTS to 'max-age=$HSTS_MAX_AGE; includeSubdomains'"
        sed -i "/add_header X-Download-Options/a add_header Strict-Transport-Security \"max-age=$HSTS_MAX_AGE; includeSubdomains\";" /etc/nginx/includes/misp
    else
        echo "... no HSTS header will be set as HSTS_MAX_AGE is not defined"
    fi

    if [ ! -f "/etc/nginx/sites-enabled/misp80" ]; then
        echo "... enabling port 80 redirect"
        ln -s /etc/nginx/sites-available/misp80 /etc/nginx/sites-enabled/misp80
    else
        echo "... port 80 already enabled"
    fi

    if [ "$DISABLE_IPV6" = "true" ]; then
        echo "... disabling IPv6 on port 80"
        sed -i "s/[^#] listen \[/  # listen \[/" /etc/nginx/sites-enabled/misp80
    else
        echo "... enabling IPv6 on port 80"
        sed -i "s/# listen \[/listen \[/" /etc/nginx/sites-enabled/misp80
    fi

    if [ "$DISABLE_SSL_REDIRECT" = "true" ]; then
        echo "... disabling SSL redirect"
        sed -i "s/[^#] return /  # return /" /etc/nginx/sites-enabled/misp80
        sed -i "s/# include /include /" /etc/nginx/sites-enabled/misp80
    else
        echo "... enabling SSL redirect"
        sed -i "s/[^#] include /  # include /" /etc/nginx/sites-enabled/misp80
        sed -i "s/# return /return /" /etc/nginx/sites-enabled/misp80
    fi

    if [ ! -f "/etc/nginx/sites-enabled/misp443" ]; then
        echo "... enabling port 443"
        ln -s /etc/nginx/sites-available/misp443 /etc/nginx/sites-enabled/misp443
    else
        echo "... port 443 already enabled"
    fi

    if [ "$DISABLE_IPV6" = "true" ]; then
        echo "... disabling IPv6 on port 443"
        sed -i "s/[^#] listen \[/  # listen \[/" /etc/nginx/sites-enabled/misp443
    else
        echo "... enabling IPv6 on port 443"
        sed -i "s/# listen \[/listen \[/" /etc/nginx/sites-enabled/misp443
    fi

    if [ ! -f /etc/nginx/certs/cert.pem ] || [ ! -f /etc/nginx/certs/key.pem ]; then
        echo "... generating new self-signed TLS certificate"
        openssl req -x509 -subj '/CN=localhost' -nodes -newkey rsa:4096 -keyout /etc/nginx/certs/key.pem -out /etc/nginx/certs/cert.pem -days 365 \
            -addext "subjectAltName = DNS:localhost, IP:127.0.0.1, IP:::1"
    else
        echo "... TLS certificates found"
    fi

    if [ ! -f /etc/nginx/certs/dhparams.pem ]; then
        echo "... generating new DH parameters"
        openssl dhparam -out /etc/nginx/certs/dhparams.pem 2048
    else
        echo "... DH parameters found"
    fi

    if [ -n "$FASTCGI_STATUS_LISTEN" ]; then
        echo "... enabling php-fpm status page"
        ln -s /etc/nginx/sites-available/php-fpm-status /etc/nginx/sites-enabled/php-fpm-status
        sed -i -E "s/ listen [^;]+/ listen $FASTCGI_STATUS_LISTEN/" /etc/nginx/sites-enabled/php-fpm-status
    elif [ -f /etc/nginx/sites-enabled/php-fpm-status ]; then
        echo "... disabling php-fpm status page"
        rm /etc/nginx/sites-enabled/php-fpm-status
    fi

    flip_nginx false false
}
flip_nginx() {
    live="$1"
    reload="$2"

    if [ "$live" = "true" ]; then
        NGINX_DOC_ROOT=/var/www/MISP/app/webroot
    elif [ -x /custom/files/var/www/html/index.php ]; then
        NGINX_DOC_ROOT=/custom/files/var/www/html/
    else
        NGINX_DOC_ROOT=/var/www/html/
    fi

    echo "... nginx docroot set to ${NGINX_DOC_ROOT}"
    sed -i "s|root.*var/www.*|root ${NGINX_DOC_ROOT};|" /etc/nginx/includes/misp

    if [ "$reload" = "true" ] && [ -z "$KUBERNETES_SERVICE_HOST" ]; then
        echo "... nginx reloaded"
        nginx -s reload
    fi
}

# Initialize nginx
echo "INIT | Initialize NGINX ..." && init_nginx
echo "INIT | Flip NGINX live ..." && flip_nginx true true

# Launch nginx as current shell process in container
exec nginx -g 'daemon off;'
