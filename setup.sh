#!/bin/bash

set -eu

source _config.sh

# Ubuntu 22.04.3
# OpenResty 1.21.4.2
# PostgreSQL 16

apt-get -y install wget gnupg ca-certificates
wget -O - https://openresty.org/package/pubkey.gpg | gpg --dearmor -o /usr/share/keyrings/openresty.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/openresty.gpg] http://openresty.org/package/ubuntu $(lsb_release -sc) main" > /etc/apt/sources.list.d/openresty.list
apt-get update
apt-get -y install openresty

mkdir $APP_HOME/www
cat > /etc/openresty/nginx.conf <<EOF
worker_processes 1;
user $APP_USER;

events {
    worker_connections 32;
}

http {
    include '$APP_HOME/www/nginx/http.conf';

    server {
        server_name $DOMAIN;

        include '$APP_HOME/www/nginx/routes.conf';
    }
}
EOF
mkdir -p $APP_HOME/www/log
chown -R $APP_USER $APP_HOME/www
# TODO: load application files
systemctl reload openresty

apt-get -y install snapd
snap install --classic certbot
certbot --non-interactive --nginx --nginx-server-root /etc/openresty --nginx-ctl /usr/bin/openresty --agree-tos --email $EMAIL --domains $DOMAIN

echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
apt-get update
apt-get install -y postgresql-16
su - postgres -c psql <<EOF
CREATE USER "$PSQL_USER" WITH PASSWORD '$PSQL_PASS';
CREATE DATABASE "$PSQL_USER" WITH OWNER "$PSQL_USER";
EOF

opm install openresty/lua-resty-string leafo/pgmoon fffonion/lua-resty-openssl
