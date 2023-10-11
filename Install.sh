#!/bin/bash

#############################################################################################
#################################### VARIABLES ##############################################
#############################################################################################

# Set a random password for the database user and the Nextcloud admin user
DB_PASS=$(openssl rand -base64 12)

#############################################################################################
#################################### TESTS #################################################
#############################################################################################

# Check if the script is being executed with superuser privileges (root).
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as a superuser (sudo)."
  exit
fi

# Check if the website is online
if ! wget --spider https://download.nextcloud.com/server/releases/latest.zip; then
    echo "The website https://download.nextcloud.com is not online. Please check your internet connection."
    exit 1
fi

#############################################################################################
#################################### LOG ####################################################
#############################################################################################

# Create a log file to record command outputs
LOG_FILE=/var/log/nextcloud_install.log
touch "$LOG_FILE"
exec > >(tee -a "$LOG_FILE")
exec 2>&1

#############################################################################################
#################################### STARTING INSTALLATION #################################
#############################################################################################

# Update the system.
apt update && apt -y full-upgrade

# Install PHP 8.2 and necessary extensions

# Prompt the user to choose between Debian and Ubuntu
echo "Welcome to the PHP installer for Debian or Ubuntu!"
while true; do
    read -p "Type '1' for Debian or '2' for Ubuntu to choose the desired distribution: " distro
    case $distro in
        1)
            # Debian
            echo "########## Installing PHP modules on Debian...##########"

            apt install apt-transport-https lsb-release ca-certificates wget -y
            wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg 
            sh -c 'echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list'
            apt update
            apt install unzip imagemagick php8.2 php8.2-{fpm,cli,curl,gd,mbstring,xml,zip,bz2,intl,bcmath,gmp,imagick,mysql} -y
            break
            ;;
        2)
            # Ubuntu
            echo "########## Installing PHP modules on Ubuntu...##########"

            apt install software-properties-common -y
            add-apt-repository ppa:ondrej/php -y
            apt update
            apt install unzip imagemagick php8.2 php8.2-{fpm,cli,curl,gd,mbstring,xml,zip,bz2,intl,bcmath,gmp,imagick,mysql} -y
            break
            ;;
        *)
            echo "Invalid choice. Please type '1' or '2'."
            ;;
    esac
done

# Install and configure the WebServer

# Prompt the user to choose between Apache and Nginx
echo "Welcome to the WebServer installer!"
while true; do
    read -p "Type '1' for Apache or '2' for Nginx: " webserver
    case $webserver in
        1)
            # Apache
            echo "########## Installing and configuring Apache...##########"

            # Install Apache
            apt install apache2 apache2-utils -y

            # Create the VirtualHost for Nextcloud
            cd /etc/apache2/sites-available
            curl -sSfL https://raw.githubusercontent.com/edsonsbj/Nextcloud/master/etc/apache/nextcloud.conf -o nextcloud.conf

            # Perform Apache configurations
            a2ensite nextcloud.conf
            a2dissite 000-default.conf
            a2enmod proxy_fcgi setenvif
            a2enmod rewrite headers env dir mime setenvif ssl
            systemctl restart apache2
            break
            ;;
        2)
            # Nginx
            echo "########## Installing and configuring Nginx...##########"

            # Install Nginx
            apt install nginx -y

            # Create the VirtualHost for Nextcloud
            cd /etc/nginx/sites-available
            curl -sSfL https://raw.githubusercontent.com/edsonsbj/Nextcloud/master/etc/nginx/nextcloud.conf -o nextcloud
            ln -s /etc/nginx/sites-available/nextcloud /etc/nginx/sites-enabled/
            rm /etc/nginx/sites-enabled/default
            sed -i 's/;clear_env = no/clear_env = no/g' /etc/php/8.2/fpm/pool.d/www.conf
            sed -i 's/;cgi.fix_pathinfo=0/cgi.fix_pathinfo=0/g' /etc/php/8.2/fpm/php.ini
            systemctl reload nginx
            break
            ;;
        *)
            echo "Invalid choice. Please type '1' or '2'."
            ;;
    esac
done

# Install MariaDB
apt install mariadb-server mariadb-client -y

# Install Redis
apt install redis-server php-redis -y
phpenmod redis
systemctl restart $webserver

# Configure PHP-FPM
sed -i 's/memory_limit = .*/memory_limit = 512M/' /etc/php/8.2/fpm/php.ini
sed -i 's/;date.timezone.*/date.timezone = America\/Sao_Paulo/' /etc/php/8.2/fpm/php.ini
sed -i 's/upload_max_filesize = .*/upload_max_filesize = 10240M/' /etc/php/8.2/fpm/php.ini
sed -i 's/post_max_size = .*/post_max_size = 10240M/' /etc/php/8.2/fpm/php.ini

# Restart and apply changes to WebServer and PHP
systemctl restart $webserver
systemctl restart php8.2-fpm

# Create the Database
mysql -e "CREATE DATABASE nextcloud;"
mysql -e "CREATE USER 'nextcloud'@'localhost' IDENTIFIED BY '$DB_PASS';"
mysql -e "GRANT ALL PRIVILEGES ON nextcloud.* TO 'nextcloud'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

# Download and install Nextcloud
cd /var/www/
wget https://download.nextcloud.com/server/releases/latest.zip
unzip latest.zip
chown -R www-data:www-data /var/www/nextcloud
chmod -R 755 /var/www/nextcloud
mkdir -p /var/nextcloud_data 
chown -R www-data:www-data /var/nextcloud_data
chmod -R 770 /var/nextcloud_data

# Configure Nextcloud
tee -a /var/www/nextcloud/config/autoconfig.php <<EOF
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

tee -a /var/www/nextcloud/config/custom.config.php <<EOF
<?php
\$CONFIG = array (
  'default_phone_region' => 'BR',
  'memcache.distributed' => '\\OC\\Memcache\\Redis',
  'memcache.local' => '\\OC\\Memcache\\Redis',
  'memcache.locking' => '\\OC\\Memcache\\Redis',
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
);
EOF

#############################################################################################
############################### FINISHING THE INSTALLATION ##################################
#############################################################################################

# Add a task to the cron
(crontab -l 2>/dev/null; echo "*/5 * * * * sudo -u www-data php /var/www/nextcloud/cron.php") | crontab -

# Install ffmpeg to enable video thumbnails
apt install ffmpeg -y

echo "Nextcloud installation has been completed successfully!"