# ----------------- Colors -----------------
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
RESET="\e[0m"

print_status() {
    local status=$1
    local msg=$2
    if [[ "$status" -eq 0 ]]; then
        echo -e "${GREEN}✅ Sukses:${RESET} $msg"
    else
        echo -e "${RED}❌ Gagal:${RESET} $msg"
    fi
}

status_overview() {
    echo -e "${CYAN}===== STATUS OVERVIEW =====${RESET}"
    if systemctl is-active --quiet $DNS_SERVICE; then
        echo -e "Unbound DNS: ${GREEN}Aktif${RESET}"
    else
        echo -e "Unbound DNS: ${RED}Nonaktif${RESET}"
    fi

    CURRENT_RPZ=$(grep -Po 'zone "\K[^"]+' $CONFIG_FILE | head -1)
    if [ "$CURRENT_RPZ" == "$RPZ_FILE" ]; then
        echo -e "RPZ: ${GREEN}Enabled${RESET}"
    else
        echo -e "RPZ: ${RED}Disabled${RESET}"
    fi

    if [ -f "$CRON_FILE" ]; then
        echo -e "Cron RPZ harian: ${GREEN}Ada${RESET}"
    else
        echo -e "Cron RPZ harian: ${RED}Tidak ada${RESET}"
    fi

    if [ -f "$LOG_FILE" ]; then
        last_update=$(grep -E "Daily RPZ update" "$LOG_FILE" | tail -1)
        echo -e "Last RPZ update: ${YELLOW}${last_update:-Belum ada}${RESET}"
    fi

    if [ -f "$BLOCK_PAGE_DOMAIN" ]; then
        echo -e "Domain Halaman Terblokir: ${YELLOW}$(cat $BLOCK_PAGE_DOMAIN)${RESET}"
    else
        echo -e "Domain Halaman Terblokir: ${RED}Belum di-set${RESET}"
    fi
    echo -e "${CYAN}============================${RESET}"
}

show_menu() {
    echo -e "${CYAN}========================================${RESET}"
    echo -e "${CYAN} Unbound DNS + RPZ Installer / Menu ${RESET}"
    echo -e "${CYAN}========================================${RESET}"
    echo -e "1) Install / Setup Unbound + RPZ"
    echo -e "2) Install Tanpa RPZ"
    echo -e "3) RPZ Management Submenu"
    echo -e "4) Restart / Status Unbound"
    echo -e "5) Lihat Log"
    echo -e "6) Turn OFF / Turn ON DNS server"
    echo -e "7) Upgrade Package Unbound"
    echo -e "8) Set Server Timezone ke Jakarta"
    echo -e "9) Set Domain Halaman Terblokir"
    echo -e "10) Status Overview"
    echo -e "11) Uninstall Unbound"
    echo -e "12) Exit"
    echo -e "${CYAN}========================================${RESET}"
}
