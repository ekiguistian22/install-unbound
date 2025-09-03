#!/bin/bash
# =====================================================
# Unbound DNS + RPZ Installer / Management / Uninstall
# All-in-One Script
# =====================================================

set -e

CONFIG_DIR="/etc/unbound"
CONFIG_FILE="$CONFIG_DIR/unbound.conf"
RPZ_DIR="$CONFIG_DIR/trustpositif"
RPZ_FILE="$RPZ_DIR/trustpositif.rpz"
PLACEHOLDER="$RPZ_DIR/placeholder.rpz"
BLOCK_PAGE_DOMAIN="$RPZ_DIR/blocked.domain"
LOG_DIR="/var/log/unbound"
LOG_FILE="$LOG_DIR/unbound.log"
CRON_FILE="/etc/cron.daily/unbound-rpz-update"
BASE_DIRS=("$CONFIG_DIR" "/var/lib/unbound" "$RPZ_DIR" "$LOG_DIR")
DNS_SERVICE="unbound"
RPZ_LINK=""
NAMESERVERS=""

# ----------------- Helper Functions -----------------
print_status() {
    local status=$1
    local msg=$2
    if [[ "$status" -eq 0 ]]; then
        echo -e "✅ Sukses: $msg"
    else
        echo -e "❌ Gagal: $msg"
    fi
}

ensure_file_exists() {
    local file=$1
    local prefix=$2
    if [ ! -f "$file" ]; then
        echo "# Auto-generated $prefix file" > "$file"
        chown unbound:unbound "$file"
        print_status $? "Membuat file $file"
    fi
}

# ----------------- Fitur -----------------
set_timezone() {
    timedatectl set-timezone Asia/Jakarta
    print_status $? "Set timezone ke Asia/Jakarta"
}

set_block_page_domain() {
    read -p "Enter domain untuk halaman blokir (misal blocked.example.com): " domain
    if [[ -n "$domain" ]]; then
        echo "$domain" > "$BLOCK_PAGE_DOMAIN"
        chown unbound:unbound "$BLOCK_PAGE_DOMAIN"
        print_status $? "Domain blokir disimpan di $BLOCK_PAGE_DOMAIN"
    else
        echo "Skip domain blokir."
    fi
}

install_unbound() {
    local use_rpz=$1
    echo "[Step] Installing Unbound & dependencies..."
    apt update -y && apt upgrade -y
    apt install unbound curl cron -y
    print_status $? "Install paket Unbound & dependencies"

    if ! id "unbound" &>/dev/null; then
        useradd -r -s /usr/sbin/nologin -d /var/lib/unbound unbound
        print_status $? "Membuat user 'unbound'"
    fi

    for dir in "${BASE_DIRS[@]}"; do
        mkdir -p "$dir"
        chown -R unbound:unbound "$dir"
        print_status $? "Membuat folder $dir"
    done

    ensure_file_exists "$PLACEHOLDER" "placeholder"
    if [[ "$use_rpz" == "yes" ]]; then
        ensure_file_exists "$RPZ_FILE" "trustpositif"
        while true; do
            read -p "Enter RPZ download link: " RPZ_LINK
            if [[ -z "$RPZ_LINK" ]]; then
                echo "Skip RPZ download."
                break
            fi
            if curl --head --silent --fail "$RPZ_LINK" > /dev/null; then
                curl -sL "$RPZ_LINK" -o "$RPZ_FILE"
                chown unbound:unbound "$RPZ_FILE"
                print_status $? "Download RPZ dari $RPZ_LINK"
                break
            else
                echo "Link invalid. Try again."
            fi
        done
    else
        RPZ_FILE="$PLACEHOLDER"
    fi

    # Nameserver input
    read -p "Enter DNS nameserver(s) (comma-separated): " NAMESERVERS

    # Forwarder
    read -p "Configure DNS forwarder? (y/n): " use_forwarder
    if [[ "$use_forwarder" == "y" ]]; then
        read -p "Enter upstream DNS (comma-separated): " upstream_dns
    fi

    # Backup old config
    [ -f "$CONFIG_FILE" ] && cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"

    # Generate unbound.conf
    cat > "$CONFIG_FILE" <<EOF
server:
    verbosity: 1
    username: "unbound"
    directory: "/var/lib/unbound"
    interface: 0.0.0.0
    port: 53
    do-ip4: yes
    do-ip6: yes
    do-udp: yes
    do-tcp: yes
    access-control: 127.0.0.0/8 allow
    access-control: 0.0.0.0/0 allow
    access-control: ::0/0 allow

    msg-cache-size: 50m
    rrset-cache-size: 100m
    cache-min-ttl: 3600
    cache-max-ttl: 86400

    response-policy:
        zone "$RPZ_FILE"

    local-zone: "$(cat $BLOCK_PAGE_DOMAIN 2>/dev/null || echo "blocked.example.com")" redirect

    logfile: "$LOG_FILE"
    log-queries: yes

remote-control:
    control-enable: yes
EOF

    if [[ "$use_forwarder" == "y" ]]; then
        echo "forward-zone:" >> "$CONFIG_FILE"
        echo "    name: ." >> "$CONFIG_FILE"
        IFS=',' read -ra ADDR <<< "$upstream_dns"
        for dns in "${ADDR[@]}"; do
            echo "    forward-addr: $dns" >> "$CONFIG_FILE"
        done
    fi

    chown -R unbound:unbound "$CONFIG_FILE"
    systemctl enable unbound
    systemctl restart unbound
    print_status $? "Unbound installed & running"
}

toggle_rpz() {
    CURRENT_RPZ=$(grep -Po 'zone "\K[^"]+' $CONFIG_FILE | head -1)
    if [ "$CURRENT_RPZ" == "$RPZ_FILE" ]; then
        sed -i "s|$RPZ_FILE|$PLACEHOLDER|" $CONFIG_FILE
        print_status $? "RPZ disabled"
    elif [ "$CURRENT_RPZ" == "$PLACEHOLDER" ]; then
        sed -i "s|$PLACEHOLDER|$RPZ_FILE|" $CONFIG_FILE
        print_status $? "RPZ enabled"
    else
        sed -i "/response-policy:/a\        zone \"$RPZ_FILE\"" $CONFIG_FILE
        print_status $? "RPZ set to enabled"
    fi
    unbound-control reload
}

update_rpz_manual() {
    read -p "Enter RPZ download link: " LINK
    if [[ -z "$LINK" ]]; then
        echo "No link provided."
        return
    fi
    backup="$RPZ_FILE.bak.$(date +%s)"
    cp "$RPZ_FILE" "$backup"
    if curl -sL "$LINK" -o "$RPZ_FILE"; then
        chown unbound:unbound "$RPZ_FILE"
        unbound-control reload
        print_status 0 "RPZ updated successfully"
    else
        mv "$backup" "$RPZ_FILE"
        unbound-control reload
        print_status 1 "RPZ update failed, restored previous version"
    fi
}

setup_cron() {
    read -p "Enter RPZ link for daily update: " LINK
    RPZ_LINK="$LINK"
    cat > "$CRON_FILE" <<EOC
#!/bin/bash
backup="$RPZ_FILE.bak.\$(date +%s)"
cp "$RPZ_FILE" "\$backup"
if curl -sL "$LINK" -o "$RPZ_FILE"; then
    chown unbound:unbound "$RPZ_FILE"
    /usr/sbin/unbound-control reload
    echo "✅ Daily RPZ update success: \$(date)" >> "$LOG_FILE"
else
    mv "\$backup" "$RPZ_FILE"
    /usr/sbin/unbound-control reload
    echo "❌ Daily RPZ update failed, restored previous version: \$(date)" >> "$LOG_FILE"
fi
EOC
    chmod +x "$CRON_FILE"
    print_status $? "Daily RPZ update cron created at $CRON_FILE"
}

toggle_dns() {
    if systemctl is-active --quiet $DNS_SERVICE; then
        systemctl stop $DNS_SERVICE
        print_status $? "DNS server turned OFF"
    else
        systemctl start $DNS_SERVICE
        print_status $? "DNS server turned ON"
    fi
}

upgrade_unbound() {
    apt update -y
    apt install --only-upgrade unbound -y
    print_status $? "Unbound package upgraded"
}

# ----------------- Status Overview -----------------
status_overview() {
    echo "===== STATUS OVERVIEW ====="
    if systemctl is-active --quiet $DNS_SERVICE; then
        echo "Unbound DNS: ✅ Aktif"
    else
        echo "Unbound DNS: ❌ Nonaktif"
    fi

    CURRENT_RPZ=$(grep -Po 'zone "\K[^"]+' $CONFIG_FILE | head -1)
    if [ "$CURRENT_RPZ" == "$RPZ_FILE" ]; then
        echo "RPZ: ✅ Enabled"
    else
        echo "RPZ: ❌ Disabled"
    fi

    if [ -f "$CRON_FILE" ]; then
        echo "Cron RPZ harian: ✅ Ada"
    else
        echo "Cron RPZ harian: ❌ Tidak ada"
    fi

    if [ -f "$LOG_FILE" ]; then
        last_update=$(grep -E "Daily RPZ update" "$LOG_FILE" | tail -1)
        echo "Last RPZ update: ${last_update:-❌ Belum ada}"
    fi

    if [ -f "$BLOCK_PAGE_DOMAIN" ]; then
        echo "Domain Halaman Terblokir: $(cat $BLOCK_PAGE_DOMAIN)"
    else
        echo "Domain Halaman Terblokir: ❌ Belum di-set"
    fi
    echo "============================"
}

# ----------------- RPZ Sub-Menu -----------------
rpz_submenu() {
    while true; do
        echo "===== RPZ Management Submenu ====="
        echo "1) Toggle RPZ enable/disable"
        echo "2) Update RPZ manual"
        echo "3) Setup / Enable Daily RPZ Update"
        echo "4) Back to Main Menu"
        read -p "Choose an option [1-4]: " subchoice
        case $subchoice in
            1) toggle_rpz ;;
            2) update_rpz_manual ;;
            3) setup_cron ;;
            4) break ;;
            *) echo "Invalid choice." ;;
        esac
        echo ""
    done
}

# ----------------- Uninstall -----------------
uninstall_unbound() {
    echo "⚠️  This will remove Unbound, RPZ, cron, folders, and user 'unbound'"
    read -p "Are you sure? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then
        echo "Uninstall cancelled."
        return
    fi

    systemctl stop $DNS_SERVICE 2>/dev/null
    systemctl disable $DNS_SERVICE 2>/dev/null
    print_status $? "Stop & disable Unbound service"

    apt purge -y unbound
    print_status $? "Remove package Unbound"

    userdel -r unbound 2>/dev/null
    print_status $? "Remove user 'unbound'"

    rm -rf "${BASE_DIRS[@]}" "$CRON_FILE"
    print_status $? "Remove all config, log, RPZ, cron files"

    echo "✅ Uninstall completed"
}

# ----------------- Main Menu -----------------
show_menu() {
    echo "========================================"
    echo " Unbound DNS + RPZ Installer / Menu"
    echo "========================================"
    echo "1) Install / Setup Unbound + RPZ"
    echo "2) Install Tanpa RPZ"
    echo "3) RPZ Management Submenu"
    echo "4) Restart / Status Unbound"
    echo "5) Lihat Log"
    echo "6) Turn OFF / Turn ON DNS server"
    echo "7) Upgrade Package Unbound"
    echo "8) Set Server Timezone ke Jakarta"
    echo "9) Set Domain Halaman Terblokir"
    echo "10) Status Overview"
    echo "11) Uninstall Unbound"
    echo "12) Exit"
    echo "========================================"
}

# ----------------- Main Loop -----------------
while true; do
    show_menu
    read -p "Choose an option [1-12]: " choice
    case $choice in
        1) install_unbound "yes" ;;
        2) install_unbound "no" ;;
        3) rpz_submenu ;;
        4) systemctl restart $DNS_SERVICE && systemctl status $DNS_SERVICE ;;
        5) less "$LOG_FILE" ;;
        6) toggle_dns ;;
        7) upgrade_unbound ;;
        8) set_timezone ;;
        9) set_block_page_domain ;;
        10) status_overview ;;
        11) uninstall_unbound ;;
        12) echo "Exiting..."; break ;;
        *) echo "Invalid choice." ;;
    esac
    echo ""
done
