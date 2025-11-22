#!/bin/bash

#############################################################################################
#################################### VARIABLES ##############################################
#############################################################################################

# PHP Version (Nextcloud 30+ recommends 8.3 or 8.4)
PHP_VER="8.3"

# Set a random password for the database user
DB_PASS=$(openssl rand -base64 12)

# Log File
LOG_FILE=/var/log/nextcloud_install.log

#############################################################################################
#################################### TESTS ##################################################
#############################################################################################

# Check if the script is being executed with superuser privileges (root).
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as superuser (sudo)."
  exit
fi

# Check internet connection
if ! wget --spider https://download.nextcloud.com/server/releases/latest.zip; then
    echo "The website https://download.nextcloud.com is not reachable. Please check your internet connection."
    exit 1
fi

#############################################################################################
#################################### LOG ####################################################
#############################################################################################

touch "$LOG_FILE"
exec > >(tee -a "$LOG_FILE")
exec 2>&1

#############################################################################################
#################################### STARTING INSTALLATION ##################################
#############################################################################################

echo "Updating the system..."
apt-get update && apt-get -y full-upgrade
apt-get install -y software-properties-common lsb-release ca-certificates wget curl unzip

# Install PHP and necessary extensions

echo "Welcome to the PHP installer!"
while true; do
    read -p "Type '1' for Debian or '2' for Ubuntu to choose the desired distribution: " distro
    case $distro in
        1)
            # Debian
            echo "########## Installing PHP on Debian...##########"
            apt-get install apt-transport-https -y
            wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg 
            sh -c 'echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list'
            apt-get update
            break
            ;;
        2)
            # Ubuntu
            echo "########## Installing PHP on Ubuntu...##########"
            add-apt-repository ppa:ondrej/php -y
            apt-get update
            break
            ;;
        *)
            echo "Invalid choice. Please type '1' or '2'."
            ;;
    esac
done

# Install PHP packages (Added apcu and exif)
echo "Installing PHP $PHP_VER and modules..."
apt-get install -y imagemagick ffmpeg \
php$PHP_VER php$PHP_VER-{fpm,cli,curl,gd,mbstring,xml,zip,bz2,intl,bcmath,gmp,imagick,mysql,apcu,exif,redis}

# Install and Configure the WebServer

echo "Welcome to the WebServer installer!"
SERVICE_NAME="" # Variable to store the correct service name

while true; do
    read -p "Type '1' for Apache or '2' for Nginx: " webserver_choice
    case $webserver_choice in
        1)
            # Apache
            SERVICE_NAME="apache2"
            echo "########## Installing and configuring Apache...##########"

            apt-get install apache2 apache2-utils -y

            # Download VirtualHost (kept as requested)
            cd /etc/apache2/sites-available
            curl -sSfL https://raw.githubusercontent.com/edsonsbj/Nextcloud/master/etc/apache/nextcloud.conf -o nextcloud.conf

            # Apache Configurations
            a2ensite nextcloud.conf
            a2dissite 000-default.conf
            a2enmod proxy_fcgi setenvif rewrite headers env dir mime ssl
            # Enable HTTP2 if available
            a2enmod http2 2>/dev/null || true
            
            systemctl restart apache2
            break
            ;;
        2)
            # Nginx
            SERVICE_NAME="nginx"
            echo "########## Installing and configuring Nginx...##########"

            apt-get install nginx -y

            # Download VirtualHost (kept as requested)
            cd /etc/nginx/sites-available
            curl -sSfL https://raw.githubusercontent.com/edsonsbj/Nextcloud/master/etc/nginx/nextcloud.conf -o nextcloud
            
            # Symbolic link
            ln -sf /etc/nginx/sites-available/nextcloud /etc/nginx/sites-enabled/
            rm -f /etc/nginx/sites-enabled/default

            # Specific Nginx adjustments for PHP-FPM
            sed -i 's/;clear_env = no/clear_env = no/g' /etc/php/$PHP_VER/fpm/pool.d/www.conf
            sed -i 's/;cgi.fix_pathinfo=0/cgi.fix_pathinfo=0/g' /etc/php/$PHP_VER/fpm/php.ini
            
            systemctl reload nginx
            break
            ;;
        *)
            echo "Invalid choice. Please type '1' or '2'."
            ;;
    esac
done

# Install MariaDB and Redis
apt-get install mariadb-server mariadb-client redis-server -y

# Restart the correct web service
systemctl restart $SERVICE_NAME

# Optimized PHP Configuration (Performance Tuning)
PHP_INI="/etc/php/$PHP_VER/fpm/php.ini"

sed -i 's/memory_limit = .*/memory_limit = 1024M/' $PHP_INI
sed -i 's/;date.timezone.*/date.timezone = America\/Sao_Paulo/' $PHP_INI
sed -i 's/upload_max_filesize = .*/upload_max_filesize = 10G/' $PHP_INI
sed -i 's/post_max_size = .*/post_max_size = 10G/' $PHP_INI
sed -i 's/max_execution_time = .*/max_execution_time = 3600/' $PHP_INI

# OPCache Tuning (CRITICAL for Nextcloud)
sed -i 's/;opcache.enable=1/opcache.enable=1/' $PHP_INI
sed -i 's/;opcache.interned_strings_buffer=.*/opcache.interned_strings_buffer=32/' $PHP_INI
sed -i 's/;opcache.max_accelerated_files=.*/opcache.max_accelerated_files=10000/' $PHP_INI
sed -i 's/;opcache.memory_consumption=.*/opcache.memory_consumption=128/' $PHP_INI
sed -i 's/;opcache.save_comments=1/opcache.save_comments=1/' $PHP_INI
sed -i 's/;opcache.revalidate_freq=.*/opcache.revalidate_freq=1/' $PHP_INI

# Restart PHP-FPM and Webserver
systemctl restart $SERVICE_NAME
systemctl restart php$PHP_VER-fpm

# Create Database (Explicit UTF8mb4)
mysql -e "CREATE DATABASE nextcloud CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
mysql -e "CREATE USER 'nextcloud'@'localhost' IDENTIFIED BY '$DB_PASS';"
mysql -e "GRANT ALL PRIVILEGES ON nextcloud.* TO 'nextcloud'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

# Download and Install Nextcloud
cd /var/www/
# Remove previous installation if exists to avoid conflict
rm -rf /var/www/nextcloud
wget https://download.nextcloud.com/server/releases/latest.zip
unzip -q latest.zip
rm latest.zip

# Create data directory outside webroot (Security)
mkdir -p /var/nextcloud_data 

# Permissions
chown -R www-data:www-data /var/www/nextcloud
chmod -R 755 /var/www/nextcloud
chown -R www-data:www-data /var/nextcloud_data
chmod -R 770 /var/nextcloud_data

# Automatic Configuration (Autoconfig)
tee /var/www/nextcloud/config/autoconfig.php <<EOF
<?php
\$AUTOCONFIG = array(
  'dbtype'        => 'mysql',
  'dbname'        => 'nextcloud',
  'dbuser'        => 'nextcloud',
  'dbpass'        => '$DB_PASS',
  'dbhost'        => 'localhost',
  'directory'     => '/var/nextcloud_data',
);
EOF

# Custom Configuration (APCu + Redis and Optimizations)
tee /var/www/nextcloud/config/custom.config.php <<EOF
<?php
\$CONFIG = array (
  'default_phone_region' => 'BR',
  'memcache.local' => '\\OC\\Memcache\\APCu',
  'memcache.locking' => '\\OC\\Memcache\\Redis',
  'memcache.distributed' => '\\OC\\Memcache\\Redis',
  'redis' => 
  array (
    'host' => 'localhost',
    'port' => 6379,
  ),
  'htaccess.RewriteBase' => '/',
  'skeletondirectory' => '',
  'enabledPreviewProviders' =>
  array (
    0 => 'OC\\Preview\\PNG',
    1 => 'OC\\Preview\\JPEG',
    2 => 'OC\\Preview\\GIF',
    3 => 'OC\\Preview\\BMP',
    4 => 'OC\\Preview\\XBitmap',
    5 => 'OC\\Preview\\Movie',
    6 => 'OC\\Preview\\PDF',
    7 => 'OC\\Preview\\MP3',
    8 => 'OC\\Preview\\TXT',
    9 => 'OC\\Preview\\MarkDown',
    10 => 'OC\\Preview\\Image',
    11 => 'OC\\Preview\\HEIC',
    12 => 'OC\\Preview\\TIFF',
  ),
  'trashbin_retention_obligation' => 'auto,30',
  'versions_retention_obligation' => 'auto,30',
  'simple_signUp_link.shown' => false,
);
EOF

#############################################################################################
############################### FINISHING THE INSTALLATION ##################################
#############################################################################################

# Cron Configuration
# Remove previous cron jobs related to nextcloud to avoid duplication
crontab -u www-data -l 2>/dev/null | grep -v "nextcloud/cron.php" | crontab -u www-data -
(crontab -u www-data -l 2>/dev/null; echo "*/5 * * * * php -f /var/www/nextcloud/cron.php") | crontab -u www-data -

echo "###############################################################"
echo "Nextcloud installation completed successfully!"
echo "PHP Version: $PHP_VER"
echo "Database: nextcloud / Password: $DB_PASS"
echo "Access your server via browser to finish setup."
echo "###############################################################"
