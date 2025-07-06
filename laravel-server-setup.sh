#!/bin/bash
set -e

check_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Требуется root пользователь"
    exit 1
  fi
}

install_nginx() {
  echo "=== Установка Nginx ==="
  apt install -y nginx
  sed -i '/http {/a \
      client_max_body_size 128M;\
      proxy_read_timeout 300;\
      proxy_connect_timeout 300;\
      proxy_send_timeout 300;' /etc/nginx/nginx.conf
  systemctl restart nginx
  systemctl enable nginx
}

configure_ufw() {
  echo "=== Установка UFW ==="
  apt install -y ufw
  ufw allow OpenSSH
  ufw allow 'Nginx Full'
  ufw --force enable
}

configure_ssh() {
  echo "=== Настройка SSH ==="
  sed -i 's/^#*PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
  sed -i 's/^#*PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config
  systemctl restart ssh || service ssh restart
}

create_admin_user() {
  echo "=== Добавление пользователя admin ==="
  read -p "Введите пароль для admin: " ADMIN_PASSWORD
  adduser --disabled-password --gecos "" admin
  echo "admin:$ADMIN_PASSWORD" | chpasswd
  usermod -aG sudo admin
}

remove_apache() {
  echo "=== Удаление Apache ==="
  apt purge -y apache2 apache2-utils apache2-bin libapache2-mod-php* || true
  apt autoremove -y
  apt autoclean
}

install_php_composer() {
  echo "=== Устанавка PHP и Composer ==="
  apt install -y php php-common php-fpm php-mysql php-sqlite3 php-zip php-gd php-mbstring php-curl php-xml php-bcmath curl unzip
  PHP_INI=$(php --ini | grep "Loaded Configuration" | awk '{print $NF}')
  sed -i "s/^max_execution_time = .*/max_execution_time = 300/" "$PHP_INI"
  sed -i "s/^max_input_time = .*/max_input_time = 600/" "$PHP_INI"
  sed -i "s/^memory_limit = .*/memory_limit = 1G/" "$PHP_INI"
  sed -i "s/^post_max_size = .*/post_max_size = 512M/" "$PHP_INI"
  sed -i "s/^upload_max_filesize = .*/upload_max_filesize = 512M/" "$PHP_INI"
  systemctl restart php*-fpm

  cd /tmp
  curl -sS https://getcomposer.org/installer -o composer-setup.php
  php composer-setup.php --install-dir=/usr/local/bin --filename=composer
  composer --version
}

install_nodejs() {
  echo "=== Устанавка Node.js ==="
  curl -sL https://deb.nodesource.com/setup_22.x -o /tmp/nodesource_setup.sh
  bash /tmp/nodesource_setup.sh
  apt install -y nodejs
}

install_mariadb() {
  echo "=== Устанавка MariaDB ==="
  apt install -y mariadb-server
  systemctl start mariadb
  systemctl enable mariadb
  mysql_secure_installation

  echo "=== Создание MariaDB пользователя ==="
  read -p "Введите пароль для MariaDB пользователя 'admin': " DB_PASS
  mysql -u root <<EOF
CREATE USER 'admin'@'%' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON *.* TO 'admin'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF
}

check_root

echo "Выберите режим:"
echo "1. Backend Server (Laravel)"
echo "2. Frontend Server (Node.js)"
echo "3. Database Server (PHP + MariaDB)"
read -p "Введите номер режима (1/2/3): " MODE

echo "=== Обновление системы ==="
apt update && apt upgrade -y

remove_apache
install_nginx
configure_ufw

case "$MODE" in
  1) install_php_composer ;;
  2) install_nodejs ;;
  3) install_php_composer; install_mariadb ;;
  *) echo "Неверный режим"; exit 1 ;;
esac

create_admin_user
configure_ssh

echo "=== Настройка сервера завершена ==="
