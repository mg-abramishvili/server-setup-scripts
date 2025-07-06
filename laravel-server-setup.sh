#!/bin/bash

set -e

if [ "$(id -u)" -ne 0 ]; then
  echo "Пожалуйста, запускайте скрипт от root"
  exit 1
fi

echo "=== Обновляем систему ==="
apt update && apt upgrade -y

echo "=== Удаляем Apache ==="
apt purge -y apache2*
apt autoremove -y
apt autoclean

echo "=== Устанавливаем Nginx ==="
apt install -y nginx

echo "=== Настраиваем nginx.conf ==="
NGINX_CONF="/etc/nginx/nginx.conf"
sed -i '/http {/a \
    client_max_body_size 128M;\
    proxy_read_timeout 300;\
    proxy_connect_timeout 300;\
    proxy_send_timeout 300;' $NGINX_CONF

echo "=== Перезапускаем Nginx ==="
systemctl restart nginx
systemctl enable nginx

echo "=== Настраиваем UFW ==="
apt install -y ufw
ufw allow OpenSSH
ufw allow 'Nginx Full'
ufw --force enable

echo "=== Устанавливаем PHP 8.2 и необходимые модули ==="
apt install -y php php-{common,fpm,mysql,zip,gd,mbstring,curl,xml,bcmath}

echo "=== Настраиваем PHP параметры ==="
PHP_INI=$(php --ini | grep "Loaded Configuration" | awk '{print $NF}')
sed -i "s/^max_execution_time = .*/max_execution_time = 300/" "$PHP_INI"
sed -i "s/^max_input_time = .*/max_input_time = 600/" "$PHP_INI"
sed -i "s/^memory_limit = .*/memory_limit = 1G/" "$PHP_INI"
sed -i "s/^post_max_size = .*/post_max_size = 512M/" "$PHP_INI"
sed -i "s/^upload_max_filesize = .*/upload_max_filesize = 512M/" "$PHP_INI"

for ext in fileinfo pdo_mysql pdo_sqlite; do
  grep -q "^extension=$ext" "$PHP_INI" || echo "extension=$ext" >> "$PHP_INI"
done

systemctl restart php*-fpm

echo "=== Устанавливаем Git ==="
apt install -y git

echo "=== Устанавливаем Composer ==="
apt install -y curl unzip
cd /tmp
curl -sS https://getcomposer.org/installer -o composer-setup.php
php composer-setup.php --install-dir=/usr/local/bin --filename=composer
composer --version

echo "=== Добавляем пользователя admin ==="
read -p "Введите пароль для пользователя admin: " ADMIN_PASSWORD
adduser --disabled-password --gecos "" admin
echo "admin:$ADMIN_PASSWORD" | chpasswd
usermod -aG sudo admin

echo "=== Настраиваем SSH ==="
SSH_CONFIG="/etc/ssh/sshd_config"
sed -i 's/^#*PermitRootLogin .*/PermitRootLogin no/' $SSH_CONFIG
sed -i 's/^#*PasswordAuthentication .*/PasswordAuthentication yes/' $SSH_CONFIG

echo "=== Перезапускаем SSH ==="
systemctl restart ssh || service ssh restart

echo "=== Настройка сервера завершена ==="
