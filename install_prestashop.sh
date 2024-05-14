#!/bin/bash

# 检查并挂载磁盘
check_and_mount_disks() {
    echo "Checking for unmounted disks..."
    lsblk
    read -p "Do you have any disk to mount? (y/n): " mount_disk
    if [ "$mount_disk" == "y" ]; then
        read -p "Enter the disk to mount (e.g., /dev/sdb1): " disk
        read -p "Enter the mount point (e.g., /mnt/data): " mount_point
        sudo mkdir -p $mount_point
        sudo mount $disk $mount_point
        echo "$disk mounted to $mount_point"
    else
        echo "No disks to mount."
    fi
}

# 升级系统和内核
upgrade_system_and_kernel() {
    echo "Updating system and upgrading kernel..."
    sudo apt update
    sudo apt upgrade -y
    sudo apt dist-upgrade -y
    sudo apt install linux-image-amd64 -y
    sudo reboot
}

# 安装 Docker 和 Docker Compose
install_docker_and_compose() {
    echo "Installing Docker and Docker Compose..."
    sudo apt update
    sudo apt install apt-transport-https ca-certificates curl gnupg2 software-properties-common -y
    curl -fsSL https://download.docker.com/linux/debian/gpg | sudo apt-key add -
    sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian $(lsb_release -cs) stable"
    sudo apt update
    sudo apt install docker-ce docker-ce-cli containerd.io -y
    sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    sudo ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
}

# 配置 LDNMP 并部署 PrestaShop
deploy_prestashop() {
    echo "Configuring LDNMP and deploying PrestaShop..."
    mkdir -p ~/prestashop/nginx

    read -p "Enter MySQL root password: " mysql_root_password
    read -p "Enter PrestaShop database name: " prestashop_db
    read -p "Enter PrestaShop database user: " prestashop_user
    read -p "Enter PrestaShop database password: " prestashop_password
    read -p "Enter your domain (e.g., www.zk828.com): " domain

    cat <<EOF > ~/prestashop/docker-compose.yml
version: '3.7'

services:
  mysql:
    image: mysql:5.7
    container_name: mysql
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: $mysql_root_password
      MYSQL_DATABASE: $prestashop_db
      MYSQL_USER: $prestashop_user
      MYSQL_PASSWORD: $prestashop_password
    volumes:
      - mysql_data:/var/lib/mysql

  php:
    image: prestashop/prestashop:1.7
    container_name: php
    restart: unless-stopped
    volumes:
      - ./prestashop:/var/www/html
    environment:
      PS_INSTALL_AUTO: 1
      PS_ERASE_DB: 1
      DB_SERVER: mysql
      DB_NAME: $prestashop_db
      DB_USER: $prestashop_user
      DB_PASSWD: $prestashop_password

  nginx:
    image: nginx:latest
    container_name: nginx
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx:/etc/nginx/conf.d
      - ./prestashop:/var/www/html
      - certs:/etc/letsencrypt

volumes:
  mysql_data:
  certs:
EOF

    cat <<EOF > ~/prestashop/nginx/default.conf
server {
    listen 80;
    server_name $domain;

    root /var/www/html;
    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass php:9000;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

    sudo docker-compose -f ~/prestashop/docker-compose.yml up -d

    read -p "Do you want to enable SSL? (y/n): " enable_ssl
    if [ "$enable_ssl" == "y" ]; then
        sudo apt update
        sudo apt install certbot -y
        sudo apt install python3-certbot-nginx -y
        sudo certbot --nginx -d $domain

        cat <<EOF > ~/prestashop/nginx/default.conf
server {
    listen 80;
    server_name $domain;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name $domain;

    ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;

    root /var/www/html;
    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass php:9000;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

        sudo docker-compose -f ~/prestashop/docker-compose.yml exec nginx nginx -s reload
    fi

    echo "PrestaShop deployed successfully. You can access it at http://$domain"
}

# 主函数
main() {
    check_and_mount_disks
    upgrade_system_and_kernel
    install_docker_and_compose
    deploy_prestashop
}

# 运行主函数
main
