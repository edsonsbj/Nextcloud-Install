#!/bin/bash

#############################################################################################
#################################### VARIAVEIS ##############################################
#############################################################################################

# Definir uma senha aleatória para o usuário do banco de dados e o usuário admin do Nextcloud
DB_PASS=$(openssl rand -base64 12)
ADMIN_PASS=$(openssl rand -base64 12)

#############################################################################################
#################################### TESTES #################################################
#############################################################################################

# Verificar se o script está sendo executado com privilégios de superusuário (root).
if [ "$EUID" -ne 0 ]; then
  echo "Por favor, execute este script como superusuário (sudo)."
  exit
fi

# Verificar se o site está online
if ! wget --spider https://download.nextcloud.com/server/releases/latest.zip; then
    echo "O site https://download.nextcloud.com não está online. Verifique a conexão com a Internet."
    exit 1
fi

#############################################################################################
#################################### FUNCTIONS ##############################################
#############################################################################################

# Função para instalar e configurar o apache
apache() {
    echo "########## Instalando e configurando Apache...##########"

    # Instala o Apache
    apt install apache2 apache2-utils -y

    # Cria o VirtualHost para o Nextcloud
    cd /etc/apache2/sites-available
    curl -sSfL https://raw.githubusercontent.com/edsonsbj/Nextcloud/master/etc/apache/nextcloud.conf?token=GHSAT0AAAAAACHGPTNLA2TQ7F7XL4TFVUI2ZJEOPSQ -o nextcloud.conf

    # Reinicia e aplica as alterações no Apache e PHP
    a2dismod php8.2
    a2enmod proxy_fcgi setenvif
    a2enconf php8.2-fpm
    a2ensite nextcloud.conf
    a2dissite 000-default.conf
    a2enmod rewrite headers env dir mime setenvif ssl
    systemctl restart apache2
    
    # Ativa o site 
    a2ensite nextcloud.conf
    a2dissite 000-default.conf
    a2enmod proxy_fcgi setenvif
    a2enmod rewrite headers env dir mime setenvif ssl
    systemctl restart apache2
}

# Função para instalar e configurar o nginx
nginx() {
    echo "########## Instalando e configurando nginx...##########"

    # Instala o nginx
    apt install nginx -y

    # Cria o VirtualHost para o Nextcloud
    cd /etc/nginx/sites-available
    curl -sSfL https://raw.githubusercontent.com/edsonsbj/Nextcloud/master/etc/nginx/nextcloud.conf?token=GHSAT0AAAAAACHGPTNKNPBEI6IISAM3GYYUZJEO75A -o nextcloud    
    ln -s /etc/nginx/sites-available/nextcloud /etc/nginx/sites-enabled/
    rm /etc/nginx/sites-enabled/default
    systemctl reload apache2    
}

#############################################################################################
#################################### LOG ####################################################
#############################################################################################

# Criar um arquivo de log para gravar as saídas dos comandos
LOG_FILE=/var/log/nextcloud_install.log
touch "$LOG_FILE"
exec > >(tee -a "$LOG_FILE")
exec 2>&1

#############################################################################################
#################################### INICIANDO INSTALAÇÃO ###################################
#############################################################################################

# Atualize o sistema.
apt update
apt -y full-upgrade

# Instala e configura o WebServer

# Solicitar ao usuário a escolha entre Apache e Nginx
echo "Bem-vindo ao instalador do WebServer!"
while true; do
    read -p "Digite '1' para Apache ou '2' Nginx: " webserver
    case $webserver in
        1)
            apache
            ;;
        2)
            nginx
            ;;
        *)
            echo "Escolha inválida. Por favor, digite '1' ou '2'."
            ;;
    esac
done

# Instala o MariaDB
apt install mariadb-server mariadb-client -y

# Instala o PHP 8.2 e extensões necessárias
# Solicitar ao usuário a escolha entre Debian e Ubuntu
echo "Bem-vindo ao instalador PHP para Debian ou Ubuntu!"
while true; do
    read -p "Digite 'Debian' ou 'Ubuntu' para escolher a distribuição desejada: " webserver
    case $webserver in
        Debian)
            # Comandos para DEBIAN
            apt install apt-transport-https lsb-release ca-certificates wget -y
            wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg 
            sh -c 'echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list'
            apt update
            apt install unzip imagemagick php8.2 php8.2-{fpm,cli,curl,gd,mbstring,xml,zip,bz2,intl,bcmath,gmp,imagick,mysql} -y
            break
            ;;
        Ubuntu)
            # Comandos para Ubuntu
            apt install software-properties-common -y
            add-apt-repository ppa:ondrej/php -y
            apt update
            apt install unzip imagemagick php8.2 php8.2-{fpm,cli,curl,gd,mbstring,xml,zip,bz2,intl,bcmath,gmp,imagick,mysql} -y
            break
            ;;
        *)
            echo "Escolha inválida. Por favor, digite 'Debian' ou 'Ubuntu'."
            ;;
    esac
done

# Instala o Redis
apt install redis-server php-redis -y

# Configura o PHP-FPM
sed -i 's/memory_limit = .*/memory_limit = 512M/' /etc/php/8.2/fpm/php.ini
sed -i 's/;date.timezone.*/date.timezone = America\/Sao_Paulo/' /etc/php/8.2/fpm/php.ini
sed -i 's/upload_max_filesize = .*/upload_max_filesize = 10240M/' /etc/php/8.2/fpm/php.ini
sed -i 's/post_max_size = .*/post_max_size = 10240M/' /etc/php/8.2/fpm/php.ini

# Reinicia e aplica as alterações no Apache e PHP
a2dismod php8.2
a2enmod proxy_fcgi setenvif
a2enconf php8.2-fpm
phpenmod redis
a2ensite nextcloud.conf
a2dissite 000-default.conf
a2enmod rewrite headers env dir mime setenvif ssl
systemctl restart apache2
systemctl restart php8.2-fpm

# Cria o Banco de Dados
mysql -e "CREATE DATABASE nextcloud;"
mysql -e "CREATE USER 'nextcloud'@'localhost' IDENTIFIED BY '$DB_PASS';"
mysql -e "GRANT ALL PRIVILEGES ON nextcloud.* TO 'nextcloud'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

# Baixa e instala o Nextcloud
wget https://download.nextcloud.com/server/releases/latest.zip
unzip latest.zip
mv nextcloud /var/www/
chown -R www-data:www-data /var/www/nextcloud
chmod -R 755 /var/www/nextcloud

# Executar o script de instalação do Nextcloud
sudo -u www-data php /var/www/nextcloud/occ maintenance:install --database "mysql" --database-name "nextcloud" --database-user "nextcloud" --database-pass "$DB_PASS" --admin-user $USER --admin-pass "$ADMIN_PASS"

# Exibir as senhas geradas no final do script
echo "As senhas geradas são as seguintes:"
echo "Senha do usuário admin do Nextcloud: '$ADMIN_PASS'"

echo "A instalação do Nextcloud foi concluída com sucesso!"
