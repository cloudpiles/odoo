#!/bin/bash

##
# This script creates a self-signed certificate and configuration file for Nginx.
# Nginx is used as a reverse proxy for Odoo.
# 
# For examples:
#   subdomain1.website.com -> using the Odoo database1.
#   subdomain2.website.com -> using the Odoo database2.
#   When a database name is mussing the database with the same name as the subdomain will be used, depending on the database
#   parameter of the Odoo configuration file.
##

if [ -z $1 ]; then
    echo "Missing subdomain!"
    echo "Usage: odoo_nginx subdomain [database]"
    echo "For example: ./odoo_nginx my.website.com TheDatabaseName"
    exit 0
fi

NGINX_CONFIG_DIR=/etc/nginx
DOMAIN="odoo2.clouder.la"
DB=$2

SSL_DIR=$NGINX_CONFIG_DIR/ssl/$DOMAIN
DOMAIN_CONFIG=$NGINX_CONFIG_DIR/sites/"$DOMAIN.conf"

#echo "Setup domain "$DOMAIN" with database "$2" - $DOMAIN_CONFIG, SSL=$SSL_DIR"

#echo "Create Self-signed cert"
mkdir -p $SSL_DIR
mkdir -p $NGINX_CONFIG_DIR/sites

#openssl ecparam -out $SSL_DIR/nginx.key -name prime256v1 -genkey
#openssl req -new -key $SSL_DIR/nginx.key -out $SSL_DIR/csr.pem -subj "/C=ES/ST=BCN/L=ES/O=Odoo/OU=IT/CN=$DOMAIN"
#openssl req -x509 -nodes -days 1000 -key $SSL_DIR/nginx.key -in $SSL_DIR/csr.pem -out $SSL_DIR/nginx.pem 
# openssl dhparam -out $SSL_DIR/dhparam.pem 4096 # This take long time

if [ -z $DB ]; then
    DB_STR=""    
else
    DB_STR="proxy_set_header X-Custom-Referrer \"$DB\";"
fi

echo -e "* Create $DOAMIN's nginx config file at $DOMAIN_CONFIG"

cat <<EOF > $DOMAIN_CONFIG
##
# You should look at the following URL's in order to grasp a solid understanding
# of Nginx configuration files in order to fully unleash the power of Nginx.
# http://wiki.nginx.org/Pitfalls
# http://wiki.nginx.org/QuickStart
# http://wiki.nginx.org/Configuration
#
# Generally, you will want to move this file somewhere, and start with a clean
# file but keep this around for reference. Or just disable in sites-enabled.
#
# Please see /usr/share/doc/nginx-doc/examples/ for more detailed examples.
##
##
# Configuration file for each subdomain <=> database.
# Should use with http.py patch, which using HTTP_X_CUSTOM_REFERRER as database name
# See https://github.com/halybang/odoo/blob/9.0/openerp/http.py
#
##
server {
    # Redirect all request to ssl
    listen 80;
    server_name $DOMAIN;
    # Strict Transport Security
    add_header Strict-Transport-Security max-age=2592000;
    return 301 https://\$host\$request_uri;
}
server {
    # Enable SSL
    listen 443 ssl;
    server_name $DOMAIN;
    
    #root /var/www/html;
    # Add index.php to the list if you are using PHP
    #index index.html index.htm index.nginx-debian.html;
    
    # Set log files
    access_log /var/log/nginx/$DOMAIN.access.log;
    error_log /var/log/nginx/$DOMAIN.error.log;
    
    keepalive_timeout 60;
    client_max_body_size 100m;
    
    # SSL Configuration
    # Self signed certs generated by the ssl-cert package
    ssl on;
    ssl_certificate $SSL_DIR/nginx.pem;
    ssl_certificate_key $SSL_DIR/nginx.key;
    #ssl_dhparam $SSL_DIR/dhparam.pem;
    ssl_prefer_server_ciphers on;
    ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
    ssl_session_cache shared:SSL:1m;
    ssl_session_timeout 10m;
    ssl_ciphers HIGH:!ADH:!MD5;
    #ssl_ciphers 'EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH';
    #ssl_ciphers "EECDH+AESGCM:EDH+AESGCM:ECDHE-RSA-AES128-GCM-SHA256:AES256+EECDH:DHE-RSA-AES128-GCM-SHA256:AES256+EDH:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-SHA384:ECDHE-RSA-AES128-SHA256:ECDHE-RSA-AES256-SHA:ECDHE-RSA-AES128-SHA:DHE-RSA-AES256-SHA256:DHE-RSA-AES128-SHA256:DHE-RSA-AES256-SHA:DHE-RSA-AES128-SHA:ECDHE-RSA-DES-CBC3-SHA:EDH-RSA-DES-CBC3-SHA:AES256-GCM-SHA384:AES128-GCM-SHA256:AES256-SHA256:AES128-SHA256:AES256-SHA:AES128-SHA:DES-CBC3-SHA:HIGH:!aNULL:!eNULL:!EXPORT:!DES:!MD5:!PSK:!RC4";
    
    # increase proxy buffer to handle some OpenERP web requests
    proxy_buffers 16 64k;
    proxy_buffer_size 128k;
    # general proxy settings
    # force timeouts if the backend dies
    proxy_connect_timeout 600s;
    proxy_send_timeout 600s;
    proxy_read_timeout 600s;
    proxy_next_upstream error timeout invalid_header http_500 http_502 http_503;
    
    # set headers
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header Host \$host;
    proxy_set_header X-Forwarded-Host \$http_host;
    proxy_set_header X-Forward-For \$proxy_add_x_forwarded_for;
    # Let the OpenERP web service know that we’re using HTTPS, otherwise
    # it will generate URL using http:// and not https://
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header Front-End-Https On;
    # Point to real database name
    #proxy_set_header X-Custom-Referrer "databasename";
    $DB_STR
    
    # by default, do not forward anything
    # proxy_redirect off;
    proxy_buffering off;
    location / {
        #try_files \$uri \$uri/ @proxy;
        proxy_pass http://odoo2;
        proxy_redirect default;
    }
    location /longpolling {
        proxy_pass http://odoo2-im;
    }
    
    # cache some static data in memory for 60mins.
    # under heavy load this should relieve stress on the OpenERP web interface a bit.
    location ~* /web/static/ {
        proxy_cache_valid 200 60m;
        proxy_buffering on;
        expires 864000;
        #try_files $uri $uri/ @proxy;
        proxy_pass http://odoo2;
        #proxy_redirect default;
        #proxy_redirect off;
    }
    location @proxy {
        proxy_pass http://odoo2;
        proxy_redirect default;
        #proxy_redirect off;
    }
    location ~ /\.ht {
        deny all;
    }
}
EOF
