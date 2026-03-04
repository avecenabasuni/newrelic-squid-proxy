#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# New Relic Squid Proxy — Uninstaller
# Author : Avecena Basuni
# License: MIT License
#
# Usage:
#   bash uninstall.sh
#   curl -sSL https://raw.githubusercontent.com/avecenabasuni/newrelic-squid-proxy/main/uninstall.sh | sudo bash
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/newrelic-squid-proxy}"
TOTAL_STEPS=3
CURRENT_STEP=0

# ─── ANSI Colors & Styles ────────────────────────────────────────────────────
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
WHITE="\e[37m"
GRAY="\e[90m"
BOLD="\e[1m"
DIM="\e[2m"
RESET="\e[0m"

CHECK="${GREEN}✔${RESET}"
CROSS="${RED}✘${RESET}"
ARROW="${CYAN}▸${RESET}"
DOT="${GRAY}·${RESET}"

# ─── Helper Functions ─────────────────────────────────────────────────────────
log_info()  { echo -e "  ${CHECK}  $1"; }
log_warn()  { echo -e "  ${YELLOW}⚠${RESET}  $1"; }
log_error() { echo -e "  ${CROSS}  ${RED}$1${RESET}"; }
prompt()    { echo -ne "  ${ARROW} $1"; }

separator() {
    echo -e "  ${GRAY}$(printf '%.0s─' {1..60})${RESET}"
}

step() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    echo ""
    echo -e "${BOLD}${CYAN}  [$CURRENT_STEP/$TOTAL_STEPS]${RESET} ${BOLD}$1${RESET}"
    echo -e "  ${GRAY}$(printf '%.0s─' {1..60})${RESET}"
}

# ─── Banner ──────────────────────────────────────────────────────────────────
echo ""
echo -e "  ${BOLD}${RED}╔══════════════════════════════════════════════════════════════╗${RESET}"
echo -e "  ${BOLD}${RED}║         New Relic Squid Proxy — Uninstaller                  ║${RESET}"
echo -e "  ${BOLD}${RED}║                                                              ║${RESET}"
echo -e "  ${BOLD}${RED}║  This will REMOVE Squid and all related configurations.      ║${RESET}"
echo -e "  ${BOLD}${RED}╚══════════════════════════════════════════════════════════════╝${RESET}"
echo ""

# ─── Root check ──────────────────────────────────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
    log_error "This script must be run as root. Try: sudo bash uninstall.sh"
    exit 1
fi

# ─── Confirmation Prompt ─────────────────────────────────────────────────────
echo -e "  ${YELLOW}WARNING: The following will be removed:${RESET}"
echo ""
echo -e "  ${DOT}  Squid package and auth helpers"
echo -e "  ${DOT}  /etc/squid          (configuration)"
echo -e "  ${DOT}  /var/log/squid      (access & cache logs)"
echo -e "  ${DOT}  /var/spool/squid    (disk cache)"
echo -e "  ${DOT}  /var/lib/squid      (SSL bump database)"
echo -e "  ${DOT}  /tmp/nr-squid-vars.json"
echo -e "  ${DOT}  New Relic Agent configs & scripts"
echo ""

CONFIRM=""
prompt "${BOLD}Are you sure you want to continue?${RESET} ${GRAY}[y/N]${RESET}: "
read -r CONFIRM < /dev/tty

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    log_warn "Uninstall cancelled. No changes were made."
    exit 0
fi

echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 1: Stop and disable Squid service
# ═══════════════════════════════════════════════════════════════════════════════
step "Stopping Squid service"

if systemctl is-active --quiet squid 2>/dev/null; then
    systemctl stop squid
    log_info "Squid service stopped"
else
    log_warn "Squid service was not running"
fi

if systemctl is-enabled --quiet squid 2>/dev/null; then
    systemctl disable squid
    log_info "Squid service disabled from boot"
else
    log_warn "Squid service was not enabled"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 2: Remove packages
# ═══════════════════════════════════════════════════════════════════════════════
step "Removing packages"

# Detect package manager
if command -v apt-get &>/dev/null; then
    echo -e "  ${ARROW}  Removing via apt..."
    apt-get remove --purge -y squid squid-openssl apache2-utils > /dev/null 2>&1 || true
    apt-get autoremove -y > /dev/null 2>&1 || true
    log_info "Packages removed (apt)"
elif command -v dnf &>/dev/null; then
    echo -e "  ${ARROW}  Removing via dnf..."
    dnf remove -y squid httpd-tools > /dev/null 2>&1 || true
    log_info "Packages removed (dnf)"
elif command -v yum &>/dev/null; then
    echo -e "  ${ARROW}  Removing via yum..."
    yum remove -y squid httpd-tools > /dev/null 2>&1 || true
    log_info "Packages removed (yum)"
elif command -v zypper &>/dev/null; then
    echo -e "  ${ARROW}  Removing via zypper..."
    zypper --non-interactive remove squid apache2-utils > /dev/null 2>&1 || true
    log_info "Packages removed (zypper)"
else
    log_warn "Package manager not detected — skipping package removal."
fi

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 3: Remove files and directories
# ═══════════════════════════════════════════════════════════════════════════════
step "Removing configuration, logs, and cache"

declare -A PATHS=(
    ["/etc/squid"]="Configuration"
    ["/var/log/squid"]="Logs"
    ["/var/spool/squid"]="Disk cache"
    ["/var/lib/squid"]="SSL bump database"
    ["/tmp/nr-squid-vars.json"]="Installer vars file"
    ["/usr/local/bin/rotate-squid-ca.sh"]="CA Rotation Script"
    ["/etc/newrelic-infra/logging.d/squid.yml"]="NR Logging Config"
    ["/etc/newrelic-infra/integrations.d/squid-metrics.yml"]="NR Metrics Config"
)

for path in "${!PATHS[@]}"; do
    label="${PATHS[$path]}"
    if [ -e "$path" ]; then
        rm -rf "$path"
        log_info "${label} removed  ${DIM}(${path})${RESET}"
    else
        echo -e "  ${DOT}  ${DIM}${label} not found — skipped${RESET}"
    fi
done

# Remove diagnostic archives
rm -f /tmp/newrelic-squid-diagnostic-*.tar.gz 2>/dev/null || true

# Remove cron job
if command -v crontab &>/dev/null; then
    if crontab -l 2>/dev/null | grep -q "rotate-squid-ca.sh"; then
        crontab -l 2>/dev/null | grep -v "rotate-squid-ca.sh" | grep -v "Rotate Squid CA" | crontab - || true
        log_info "CA rotation cron job removed"
    fi
fi

# ─── Final Banner ─────────────────────────────────────────────────────────────
echo ""
separator
echo ""
echo -e "  ${CHECK}  ${BOLD}${GREEN}Uninstall complete!${RESET}"
echo ""
echo -e "  ${DOT}  Squid Proxy and all related files have been removed."
if [ -d "$INSTALL_DIR" ]; then
    echo ""
    echo -e "  ${YELLOW}⚠${RESET}  The installer directory still exists at:"
    echo -e "     ${DIM}${INSTALL_DIR}${RESET}"
    echo ""
    prompt "Remove installer directory too? ${GRAY}[y/N]${RESET}: "
    read -r REMOVE_DIR < /dev/tty
    if [[ "$REMOVE_DIR" =~ ^[Yy]$ ]]; then
        rm -rf "$INSTALL_DIR"
        log_info "Installer directory removed: ${INSTALL_DIR}"
    else
        echo -e "  ${DOT}  Kept: ${DIM}${INSTALL_DIR}${RESET}"
    fi
fi
echo ""
