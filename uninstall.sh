#!/bin/bash

# =============================================================================================
#                                  NEXTCLOUD UNINSTALLER (PRO v2)
# =============================================================================================

# Root Check
if [ "$EUID" -ne 0 ]; then echo "Please run this script as root (sudo)."; exit 1; fi

clear
echo "################################################################"
echo "           NEXTCLOUD UNINSTALLER - SMART MODE"
echo "################################################################"
echo "--> Detecting installation..."

# --- 1. IMPROVED DETECTION LOGIC ---

NEXTCLOUD_DIR=""
NEXTCLOUD_DATADIR=""
DETECTED_WEBSERVER="none"

# A) Try detecting via Webserver Configs (Parsing 'root' or 'DocumentRoot')
if [ -f "/etc/nginx/sites-enabled/nextcloud" ]; then
    DETECTED_WEBSERVER="nginx"
    # Improved grep: handles tabs, spaces and semicolons better
    NEXTCLOUD_DIR=$(grep -E "^\s*root" /etc/nginx/sites-enabled/nextcloud | awk '{print $2}' | tr -d ';')
elif [ -f "/etc/apache2/sites-enabled/nextcloud.conf" ]; then
    DETECTED_WEBSERVER="apache"
    NEXTCLOUD_DIR=$(grep -E "^\s*DocumentRoot" /etc/apache2/sites-enabled/nextcloud.conf | awk '{print $2}' | tr -d '"')
fi

# B) Fallback: Physical Check (If web config parsing failed)
# We check if 'occ' exists in common locations
if [ -z "$NEXTCLOUD_DIR" ] || [ ! -d "$NEXTCLOUD_DIR" ]; then
    if [ -f "/var/www/html/nextcloud/occ" ]; then 
        NEXTCLOUD_DIR="/var/www/html/nextcloud"
    elif [ -f "/var/www/nextcloud/occ" ]; then 
        NEXTCLOUD_DIR="/var/www/nextcloud"
    fi
fi

# C) Detect Data Directory using Nextcloud Config (Most accurate method)
if [ -n "$NEXTCLOUD_DIR" ] && [ -f "$NEXTCLOUD_DIR/config/config.php" ]; then
    NEXTCLOUD_DATADIR=$(php -r "include '$NEXTCLOUD_DIR/config/config.php'; echo \$CONFIG['datadirectory'];" 2>/dev/null)
fi

# D) Fallback Data Dir
if [ -z "$NEXTCLOUD_DATADIR" ]; then NEXTCLOUD_DATADIR="/var/nextcloud_data"; fi

# Report Findings
echo "    Web Server:   $DETECTED_WEBSERVER"
echo "    Install Path: ${NEXTCLOUD_DIR:-"Not Found (Will use defaults)"}"
echo "    Data Path:    $NEXTCLOUD_DATADIR"
echo ""

# --- 2. MODE SELECTION ---

echo "################################################################"
echo " CHOOSE UNINSTALLATION MODE:"
echo "################################################################"
echo " 1) SURGICAL REMOVAL (Production Safe)"
echo "    - Removes Nextcloud App & Database."
echo "    - KEEPS Nginx, PHP, MariaDB installed (Safe for other sites)."
echo ""
echo " 2) FULL WIPE (Reset Server)"
echo "    - Removes EVERYTHING (Nextcloud + Webserver + PHP + Database)."
echo "    - WARNING: This will delete ALL databases on the server."
echo ""
read -p "Select Option [1 or 2]: " MODE_CHOICE

if [[ "$MODE_CHOICE" != "1" && "$MODE_CHOICE" != "2" ]]; then
    echo "Invalid option. Aborting."
    exit 1
fi

# --- 3. DATA PRESERVATION QUESTION (NEW FEATURE) ---

echo ""
echo "----------------------------------------------------------------"
echo " DATA PRESERVATION CHECK"
echo "----------------------------------------------------------------"
echo " Your user files (photos, docs) are located at:"
echo " -> $NEXTCLOUD_DATADIR"
echo ""
echo " Do you want to DELETE these files?"
echo "   y = Delete everything (Files are gone forever)"
echo "   n = KEEP user data (Safe for reinstall/migration)"
echo ""
read -p "Delete User Data? (y/n): " DELETE_DATA

echo ""
echo "Summary:"
if [ "$MODE_CHOICE" == "1" ]; then echo "- Mode: Surgical Removal"; else echo "- Mode: Full System Wipe"; fi
if [[ "$DELETE_DATA" == "y" ]]; then echo "- Data: DELETE ($NEXTCLOUD_DATADIR)"; else echo "- Data: KEEP ($NEXTCLOUD_DATADIR)"; fi
echo ""

read -p "Are you sure you want to proceed? (y/n): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then echo "Aborted."; exit 1; fi

# =============================================================================================
#                                  EXECUTION
# =============================================================================================

echo ""
echo "--> [1/5] Removing Nextcloud Application..."

# Remove Install Directory (The Code)
if [ -n "$NEXTCLOUD_DIR" ] && [ -d "$NEXTCLOUD_DIR" ]; then
    rm -rf "$NEXTCLOUD_DIR"
    echo "    Removed App Files: $NEXTCLOUD_DIR"
fi
# Cleanup common fallbacks just in case detection missed something but folder exists
rm -rf /var/www/nextcloud 2>/dev/null
rm -rf /var/www/html/nextcloud 2>/dev/null

# Remove Data Directory (ONLY IF REQUESTED)
if [[ "$DELETE_DATA" == "y" || "$DELETE_DATA" == "Y" ]]; then
    if [ -d "$NEXTCLOUD_DATADIR" ] && [[ "$NEXTCLOUD_DATADIR" != "/" ]]; then
        rm -rf "$NEXTCLOUD_DATADIR"
        echo "    Removed User Data: $NEXTCLOUD_DATADIR"
    else
        echo "    Data directory not found or unsafe to delete."
    fi
else
    echo "    [SKIP] User Data preserved at: $NEXTCLOUD_DATADIR"
fi

echo "--> [2/5] Removing Web Configs..."
# Nginx
rm -f /etc/nginx/sites-enabled/nextcloud 2>/dev/null
rm -f /etc/nginx/sites-available/nextcloud 2>/dev/null
systemctl reload nginx 2>/dev/null
# Apache
if [ -f /etc/apache2/sites-available/nextcloud.conf ]; then
    a2dissite nextcloud.conf 2>/dev/null
    rm -f /etc/apache2/sites-available/nextcloud.conf
    systemctl reload apache2 2>/dev/null
fi

echo "--> [3/5] Cleaning Database..."
if command -v mysql >/dev/null; then
    # Surgical: Drop only nextcloud DB
    mysql -e "DROP DATABASE IF EXISTS nextcloud;" 2>/dev/null
    mysql -e "DROP USER IF EXISTS 'nextcloud'@'localhost';" 2>/dev/null
    mysql -e "DROP USER IF EXISTS 'nextcloud'@'127.0.0.1';" 2>/dev/null
    echo "    Nextcloud Database dropped."
fi

echo "--> [4/5] Cleaning Cron..."
crontab -u www-data -l 2>/dev/null | grep -v "nextcloud" | crontab -u www-data - 2>/dev/null

# --- FULL WIPE SECTION ---
if [ "$MODE_CHOICE" == "2" ]; then
    echo "--> [5/5] Performing Full System Wipe (Packages)..."
    
    systemctl stop nginx apache2 php*-fpm mariadb mysql redis-server 2>/dev/null
    
    DEBIAN_FRONTEND=noninteractive apt-get purge -y "php*" "libapache2-mod-php*"
    DEBIAN_FRONTEND=noninteractive apt-get purge -y nginx nginx-common nginx-core
    DEBIAN_FRONTEND=noninteractive apt-get purge -y apache2 apache2-utils apache2-data apache2-bin
    DEBIAN_FRONTEND=noninteractive apt-get purge -y mariadb-server mariadb-client mysql-common mariadb-common
    DEBIAN_FRONTEND=noninteractive apt-get purge -y redis-server
    
    # Cleanup Configs
    rm -rf /etc/php /etc/nginx /etc/apache2 /etc/mysql /etc/redis
    rm -rf /var/lib/mysql /var/lib/php /var/lib/redis
    
    # Cleanup Systemd Vaccines
    rm -rf /etc/systemd/system/php*-fpm.service.d/
    
    # Cleanup Repos
    add-apt-repository --remove ppa:ondrej/php -y 2>/dev/null
    rm -f /etc/apt/trusted.gpg.d/php.gpg /etc/apt/sources.list.d/php.list
    apt-get autoremove -y
    apt-get clean
    
    if command -v aa-teardown &> /dev/null; then aa-teardown 2>/dev/null; fi
    
    echo "    Full Wipe Completed."
fi

# Logs
rm -f nextcloud_install.log
rm -f install.sh

echo ""
echo "###############################################################"
echo " UNINSTALLATION FINISHED"
echo "###############################################################"
if [[ "$DELETE_DATA" != "y" && "$DELETE_DATA" != "Y" ]]; then
    echo " REMINDER: Your data is still safe at: $NEXTCLOUD_DATADIR"
fi
echo "###############################################################"