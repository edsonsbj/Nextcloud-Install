#!/bin/bash

# =============================================================================================
#                                  NEXTCLOUD INSTALLER (MASTER COMPLETE)
# =============================================================================================

# --- VARIABLES ---
PHP_VER="8.3"
DB_PASS=$(openssl rand -base64 12)
LOG_FILE="/var/log/nextcloud_install.log"

# PATHS (Fully Configurable)
NEXTCLOUD_DIR="/var/www/nextcloud"
NEXTCLOUD_DATADIR="/srv/nextcloud/data"  # Can be changed to /mnt/hdd/nextcloud_data, etc.

# REPOSITORY
REPO_URL="https://raw.githubusercontent.com/edsonsbj/Nextcloud-Install/master"

# CRITICAL FIX: Detects exactly where this script file is located
# This allows running the script from any folder (e.g., /root) and still finding local config files
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# --- ROOT CHECK ---
if [ "$EUID" -ne 0 ]; then echo "Please run as root (sudo)."; exit 1; fi

# --- LOG SETUP ---
touch "$LOG_FILE"
exec > >(tee -a "$LOG_FILE")
exec 2>&1

clear
echo "################################################################"
echo "           NEXTCLOUD INSTALLER - MASTER VERSION"
echo "################################################################"
echo ""

# ============================ 1. AUTO-DETECT OS ==============================================
echo "--> Detecting Operating System..."

if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID=$ID
    OS_LIKE=$ID_LIKE
else
    echo "Error: Cannot detect OS."
    exit 1
fi

if [[ "$OS_ID" == "debian" ]]; then
    echo "    Detected: Debian ($VERSION_ID)"
    DISTRO_MODE="debian"
elif [[ "$OS_ID" == "ubuntu" || "$OS_ID" == "zorin" || "$OS_LIKE" == *"ubuntu"* ]]; then
    echo "    Detected: $PRETTY_NAME (Ubuntu based)"
    DISTRO_MODE="ubuntu"
else
    echo "Error: Unsupported OS. Use Debian or Ubuntu."
    exit 1
fi

# ============================ 2. SELECT WEBSERVER ============================================
echo ""
echo "Select Web Server:"
echo "1) Apache"
echo "2) Nginx (Recommended)"
read -p "Choice [1/2]: " webserver_choice

echo ""
echo "--> [1/9] Preparing environment..."

# ============================ 3. SYSTEMD VACCINE =============================================
# Prevents apt from hanging on service start
echo -e '#!/bin/sh\nexit 101' > /usr/sbin/policy-rc.d
chmod +x /usr/sbin/policy-rc.d

# ============================ 4. REPOSITORIES ================================================
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y software-properties-common lsb-release ca-certificates wget curl unzip apparmor-utils gnupg2

if [ "$DISTRO_MODE" == "debian" ]; then
    wget -qO - https://packages.sury.org/php/apt.gpg | apt-key add -
    echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list
else
    add-apt-repository ppa:ondrej/php -y
fi
apt-get update

# ============================ 5. PACKAGES ====================================================
echo "--> [2/9] Installing PHP $PHP_VER, Database and Tools..."
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    mariadb-server mariadb-client redis-server \
    php$PHP_VER-fpm php$PHP_VER-cli php$PHP_VER-common php$PHP_VER-curl php$PHP_VER-gd \
    php$PHP_VER-mbstring php$PHP_VER-xml php$PHP_VER-zip php$PHP_VER-bz2 php$PHP_VER-intl \
    php$PHP_VER-bcmath php$PHP_VER-gmp php$PHP_VER-imagick php$PHP_VER-mysql php$PHP_VER-apcu \
    php$PHP_VER-redis imagemagick ffmpeg

if [ "$webserver_choice" == "1" ]; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y apache2 apache2-utils
else
    DEBIAN_FRONTEND=noninteractive apt-get install -y nginx
fi

# ============================ 6. SYSTEM HARDENING FIXES ======================================
echo "--> [3/9] Applying system fixes..."

# Patch Systemd (Timeout Fix)
mkdir -p /etc/systemd/system/php$PHP_VER-fpm.service.d/
echo -e "[Service]\nType=simple" > /etc/systemd/system/php$PHP_VER-fpm.service.d/override.conf
systemctl daemon-reload
rm -f /usr/sbin/policy-rc.d

# Fix AppArmor (Access Denied Fix)
if aa-status --enabled 2>/dev/null; then
    aa-complain /etc/apparmor.d/php*-fpm 2>/dev/null || true
fi

# Lock PHP Version
update-alternatives --set php /usr/bin/php$PHP_VER 2>/dev/null || true
update-alternatives --set phar /usr/bin/phar$PHP_VER 2>/dev/null || true

# ============================ 7. PHP CONFIGURATION ===========================================
echo "--> [4/9] Optimizing PHP..."
PHP_INI="/etc/php/$PHP_VER/fpm/php.ini"
WWW_CONF="/etc/php/$PHP_VER/fpm/pool.d/www.conf"

sed -i 's/memory_limit = .*/memory_limit = 512M/' $PHP_INI
sed -i 's/upload_max_filesize = .*/upload_max_filesize = 10G/' $PHP_INI
sed -i 's/post_max_size = .*/post_max_size = 10G/' $PHP_INI
sed -i 's/max_execution_time = .*/max_execution_time = 3600/' $PHP_INI
sed -i 's/;opcache.interned_strings_buffer=8/opcache.interned_strings_buffer=32/' $PHP_INI
sed -i 's/;opcache.save_comments=1/opcache.save_comments=1/' $PHP_INI
sed -i 's/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=1/' $PHP_INI 

# Rewrite Pool (Security Limit Extensions Fix)
cat <<EOF > $WWW_CONF
[www]
user = www-data
group = www-data
listen = /run/php/php$PHP_VER-fpm.sock
listen.owner = www-data
listen.group = www-data
listen.mode = 0660
pm = dynamic
pm.max_children = 10
pm.start_servers = 3
pm.min_spare_servers = 2
pm.max_spare_servers = 5
security.limit_extensions = 
clear_env = no
EOF

# ============================ 8. WEBSERVER CONFIG (HYBRID MODE) ==============================
echo "--> [5/9] Configuring WebServer..."

if [ "$webserver_choice" == "1" ]; then
    # --- APACHE ---
    a2dismod php$PHP_VER 2>/dev/null
    a2enmod proxy_fcgi setenvif rewrite headers env dir mime ssl http2
    
    # HYBRID LOGIC: Check local file first using SCRIPT_DIR
    if [ -f "$SCRIPT_DIR/etc/apache/nextcloud.conf" ]; then
        echo "    Using local config: $SCRIPT_DIR/etc/apache/nextcloud.conf"
        cp "$SCRIPT_DIR/etc/apache/nextcloud.conf" /etc/apache2/sites-available/nextcloud.conf
    else
        echo "    Downloading config from GitHub..."
        curl -sSfL "$REPO_URL/etc/apache/nextcloud.conf" -o /etc/apache2/sites-available/nextcloud.conf
    fi
    
    # Dynamic PHP Version replacement
    sed -i "s|php.*-fpm.sock|php$PHP_VER-fpm.sock|g" /etc/apache2/sites-available/nextcloud.conf
    
    a2ensite nextcloud.conf
    a2dissite 000-default.conf
else
    # --- NGINX ---
    
    # HYBRID LOGIC: Check local file first using SCRIPT_DIR
    if [ -f "$SCRIPT_DIR/etc/nginx/nextcloud.conf" ]; then
        echo "    Using local config: $SCRIPT_DIR/etc/nginx/nextcloud.conf"
        cp "$SCRIPT_DIR/etc/nginx/nextcloud.conf" /etc/nginx/sites-available/nextcloud
    else
        echo "    Downloading config from GitHub..."
        curl -sSfL "$REPO_URL/etc/nginx/nextcloud.conf" -o /etc/nginx/sites-available/nextcloud
    fi
    
    # Dynamic PHP Version replacement
    sed -i "s|php.*-fpm.sock|php$PHP_VER-fpm.sock|g" /etc/nginx/sites-available/nextcloud
    
    ln -sf /etc/nginx/sites-available/nextcloud /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
fi

# ============================ 9. DATABASE (TCP MODE) =========================================
echo "--> [6/9] Configuring Database..."
# Force Bind Address to allow 127.0.0.1 connection (Bypass Socket)
sed -i "s/bind-address.*/bind-address = 127.0.0.1/" /etc/mysql/mariadb.conf.d/50-server.cnf

systemctl restart mariadb
systemctl restart redis-server
systemctl enable php$PHP_VER-fpm
systemctl restart php$PHP_VER-fpm
if [ "$webserver_choice" == "1" ]; then systemctl restart apache2; else systemctl restart nginx; fi

echo "--> [7/9] Creating Database..."
mysql -e "DROP DATABASE IF EXISTS nextcloud;"
mysql -e "DROP USER IF EXISTS 'nextcloud'@'localhost';"
mysql -e "DROP USER IF EXISTS 'nextcloud'@'127.0.0.1';"
mysql -e "CREATE DATABASE nextcloud CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
mysql -e "CREATE USER 'nextcloud'@'127.0.0.1' IDENTIFIED BY '$DB_PASS';"
mysql -e "GRANT ALL PRIVILEGES ON nextcloud.* TO 'nextcloud'@'127.0.0.1';"
mysql -e "FLUSH PRIVILEGES;"

# ============================ 10. NEXTCLOUD FILES ============================================
echo "--> [8/9] Downloading Nextcloud..."
rm -rf $NEXTCLOUD_DIR
cd /var/www
wget -q https://download.nextcloud.com/server/releases/latest.zip
unzip -q latest.zip
rm latest.zip

mkdir -p $NEXTCLOUD_DATADIR 
chown -R www-data:www-data $NEXTCLOUD_DIR
chown -R www-data:www-data $NEXTCLOUD_DATADIR
chmod -R 755 $NEXTCLOUD_DIR
chmod -R 770 $NEXTCLOUD_DATADIR

# ============================ 11. CONFIGURATION (HYBRID MODE) ================================
echo "--> [9/9] Applying configurations..."

# --- AUTOCONFIG ---
# Check local using SCRIPT_DIR, else download
if [ -f "$SCRIPT_DIR/config/autoconfig.php" ]; then
    echo "    Using local autoconfig..."
    cp "$SCRIPT_DIR/config/autoconfig.php" "$NEXTCLOUD_DIR/config/autoconfig.php"
else
    echo "    Downloading autoconfig..."
    curl -sSfL "$REPO_URL/config/autoconfig.php" -o "$NEXTCLOUD_DIR/config/autoconfig.php"
fi

# INJECTION: Password & Data Directory
# Uses | delimiter because paths contain /
sed -i "s/DB_PASS_REPLACE/$DB_PASS/g" "$NEXTCLOUD_DIR/config/autoconfig.php"
sed -i "s|NEXTCLOUD_DATADIR_REPLACE|$NEXTCLOUD_DATADIR|g" "$NEXTCLOUD_DIR/config/autoconfig.php"

# --- CUSTOM CONFIG ---
# Check local using SCRIPT_DIR, else download
if [ -f "$SCRIPT_DIR/config/custom.config.php" ]; then
    echo "    Using local custom config..."
    cp "$SCRIPT_DIR/config/custom.config.php" "$NEXTCLOUD_DIR/config/custom.config.php"
else
    echo "    Downloading custom config..."
    curl -sSfL "$REPO_URL/config/custom.config.php" -o "$NEXTCLOUD_DIR/config/custom.config.php"
fi

# Force Clean Setup
rm -f "$NEXTCLOUD_DIR/config/config.php"

# Cron
(crontab -u www-data -l 2>/dev/null; echo "*/5 * * * * php -f $NEXTCLOUD_DIR/cron.php") | crontab -u www-data -

# Detect IP
SERVER_IP=$(hostname -I | awk '{print $1}')

echo "###############################################################"
echo " INSTALLATION COMPLETED!"
echo "###############################################################"
echo " 1. Access: http://$SERVER_IP"
echo "    (Or http://localhost)"
echo " 2. Create your 'Admin' user."
echo "    (Database fields are already filled)"
echo ""
echo " OS:   $DISTRO_MODE"
echo " Path: $NEXTCLOUD_DIR"
echo " Data: $NEXTCLOUD_DATADIR"
echo "###############################################################"