#!/bin/bash
set -e

check_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Требуется root пользователь"
    exit 1
  fi
}

update_system() {
  echo "=== Обновление системы ==="
  apt update && apt upgrade -y
  apt install -y curl unzip
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
  apt purge -y apache2
  apt autoremove -y
  apt autoclean
}

install_git() {
  echo "=== Устанавка Git ==="
  apt install -y git
}

install_php() {
  echo "=== Устанавка PHP и Composer ==="
  apt install -y php php-common php-fpm php-mysql php-sqlite3 php-zip php-gd php-mbstring php-curl php-xml php-bcmath
  PHP_INI=$(php --ini | grep "Loaded Configuration" | awk '{print $NF}')
  sed -i "s/^max_execution_time = .*/max_execution_time = 300/" "$PHP_INI"
  sed -i "s/^max_input_time = .*/max_input_time = 600/" "$PHP_INI"
  sed -i "s/^memory_limit = .*/memory_limit = 1G/" "$PHP_INI"
  sed -i "s/^post_max_size = .*/post_max_size = 512M/" "$PHP_INI"
  sed -i "s/^upload_max_filesize = .*/upload_max_filesize = 512M/" "$PHP_INI"
  
  systemctl restart php8.2-fpm
}

install_composer() {
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

install_phpmyadmin() {
  echo "=== Установка phpMyAdmin ==="

  export DEBIAN_FRONTEND=noninteractive
  apt install -y --no-install-recommends phpmyadmin

  rm -f /etc/apache2/conf-enabled/phpmyadmin.conf

  echo "=== Настройка Nginx для phpMyAdmin ==="
  NGINX_CONF="/etc/nginx/sites-available/phpmyadmin"
  cat > "$NGINX_CONF" <<EOF
server {
    listen 80;
    server_name _;

    root /usr/share/phpmyadmin;
    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.2-fpm.sock;
    }

    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)\$ {
        expires max;
        log_not_found off;
    }
}
EOF

  ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/phpmyadmin
  rm -f /etc/nginx/sites-enabled/default
  systemctl reload nginx
}

check_root

echo "Выберите режим:"
echo "1. Backend Server (Laravel)"
echo "2. Frontend Server (Node.js)"
echo "3. Database Server (PHP + MariaDB)"
read -p "Введите номер режима (1/2/3): " MODE

update_system
install_nginx
configure_ufw
install_git

case "$MODE" in
  1) install_php; install_composer ;;
  2) install_nodejs ;;
  3) install_php; install_mariadb; install_phpmyadmin ;;
  *) echo "Неверный режим"; exit 1 ;;
esac

remove_apache
create_admin_user
configure_ssh

echo "=== Настройка сервера завершена ==="
