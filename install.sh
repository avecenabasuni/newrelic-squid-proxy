#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# New Relic Squid Proxy — Bootstrap Installer
# Author : Avecena Basuni
# License: MIT License
#
# Usage:
#   curl -sSL https://raw.githubusercontent.com/avecenabasuni/newrelic-squid-proxy/main/install.sh | bash
#
# Override repo URL:
#   REPO_URL=https://github.com/my-fork/newrelic-squid-proxy.git bash install.sh
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ─── Configurable Repository Source ───────────────────────────────────────────
REPO_URL="${REPO_URL:-https://github.com/avecenabasuni/newrelic-squid-proxy.git}"
REPO_BRANCH="${REPO_BRANCH:-main}"
INSTALL_DIR="${INSTALL_DIR:-/opt/newrelic-squid-proxy}"
VARS_FILE="/tmp/nr-squid-vars.json"
TOTAL_STEPS=7

# ─── ANSI Colors & Styles ────────────────────────────────────────────────────
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
MAGENTA="\e[35m"
CYAN="\e[36m"
WHITE="\e[37m"
GRAY="\e[90m"
BOLD="\e[1m"
DIM="\e[2m"
RESET="\e[0m"

# ─── UI Constants ────────────────────────────────────────────────────────────
CHECK="${GREEN}✔${RESET}"
CROSS="${RED}✘${RESET}"
ARROW="${CYAN}▸${RESET}"
DOT="${GRAY}·${RESET}"
CURRENT_STEP=0

# ─── Helper Functions ─────────────────────────────────────────────────────────
log_info()  { echo -e "  ${CHECK}  $1"; }
log_warn()  { echo -e "  ${YELLOW}⚠${RESET}  $1"; }
log_error() { echo -e "  ${CROSS}  ${RED}$1${RESET}"; }

step() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    echo ""
    echo -e "${BOLD}${CYAN}  [$CURRENT_STEP/$TOTAL_STEPS]${RESET} ${BOLD}$1${RESET}"
    echo -e "  ${GRAY}$(printf '%.0s─' {1..60})${RESET}"
}

separator() {
    echo -e "  ${GRAY}$(printf '%.0s─' {1..60})${RESET}"
}

prompt() {
    echo -ne "  ${ARROW} $1"
}

banner() {
    echo ""
    echo -e "${BOLD}${CYAN}"
    echo "  ╔═══════════════════════════════════════════════════════════╗"
    echo "  ║                                                           ║"
    echo "  ║        🦑  New Relic Squid Proxy Installer                ║"
    echo "  ║                                                           ║"
    echo "  ║        Automated proxy setup for New Relic POC            ║"
    echo "  ║        environments with SSL Bump & Auth support          ║"
    echo "  ║                                                           ║"
    echo -e "  ║  ${RESET}${DIM}Author  : Avecena Basuni${RESET}${BOLD}${CYAN}                                 ║"
    echo -e "  ║  ${RESET}${DIM}License : MIT License${RESET}${BOLD}${CYAN}                                    ║"
    echo -e "  ║  ${RESET}${DIM}Version : 2.0.0${RESET}${BOLD}${CYAN}                                          ║"
    echo "  ║                                                           ║"
    echo "  ╚═══════════════════════════════════════════════════════════╝"
    echo -e "${RESET}"
}

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 1: Banner & Root Check
# ═══════════════════════════════════════════════════════════════════════════════
banner

step "Checking prerequisites"

if [ "$(id -u)" -ne 0 ]; then
    log_error "This script must be run as root or with sudo."
    echo -e "  ${GRAY}Usage: sudo bash install.sh${RESET}"
    exit 1
fi
log_info "Running as ${BOLD}root${RESET}"

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 2: Detect OS & Package Manager
# ═══════════════════════════════════════════════════════════════════════════════
step "Detecting system environment"

OS_ID=""
OS_VERSION=""
PKG_MANAGER=""

if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_VERSION="${VERSION_ID:-unknown}"
else
    log_error "Cannot detect OS — /etc/os-release not found."
    exit 1
fi

case "$OS_ID" in
    ubuntu|debian)
        PKG_MANAGER="apt"
        ;;
    centos|rhel)
        if command -v dnf &>/dev/null; then
            PKG_MANAGER="dnf"
        else
            PKG_MANAGER="yum"
        fi
        ;;
    rocky|almalinux|fedora)
        PKG_MANAGER="dnf"
        ;;
    sles|opensuse-leap|opensuse-tumbleweed)
        PKG_MANAGER="zypper"
        ;;
    *)
        log_error "Unsupported OS: $OS_ID $OS_VERSION"
        echo -e "  ${GRAY}Supported: Ubuntu, Debian, CentOS, RHEL, Rocky, Alma, Fedora, SLES, openSUSE${RESET}"
        exit 1
        ;;
esac

log_info "OS detected  : ${BOLD}${OS_ID} ${OS_VERSION}${RESET}"
log_info "Pkg manager  : ${BOLD}${PKG_MANAGER}${RESET}"

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 3: Install Ansible
# ═══════════════════════════════════════════════════════════════════════════════
step "Setting up Ansible"

ANSIBLE_MIN_VERSION="2.14"

check_ansible_version() {
    if ! command -v ansible-playbook &>/dev/null; then
        return 1
    fi

    local current_version
    current_version=$(ansible --version 2>/dev/null | head -1 | grep -oP '[\d]+\.[\d]+' | head -1)

    if [ -z "$current_version" ]; then
        return 1
    fi

    if printf '%s\n%s' "$ANSIBLE_MIN_VERSION" "$current_version" | sort -V | head -1 | grep -q "^${ANSIBLE_MIN_VERSION}$"; then
        log_info "Ansible ${BOLD}v${current_version}${RESET} detected ${GREEN}(>= ${ANSIBLE_MIN_VERSION})${RESET}"
        return 0
    else
        log_warn "Ansible ${BOLD}v${current_version}${RESET} is below minimum ${ANSIBLE_MIN_VERSION}"
        return 1
    fi
}

install_ansible() {
    echo -e "  ${ARROW} Installing Ansible via ${BOLD}${PKG_MANAGER}${RESET}..."

    case "$PKG_MANAGER" in
        apt)
            apt-get update -y -qq >/dev/null 2>&1
            apt-get install -y -qq ansible >/dev/null 2>&1
            ;;
        yum)
            yum install -y -q epel-release 2>/dev/null || true
            yum install -y -q ansible >/dev/null 2>&1
            ;;
        dnf)
            dnf install -y -q ansible-core >/dev/null 2>&1
            ;;
        zypper)
            zypper --non-interactive --quiet install ansible >/dev/null 2>&1
            ;;
    esac

    if ! check_ansible_version; then
        log_warn "Package manager install insufficient. Trying pip3..."
        install_ansible_pip
    fi
}

install_ansible_pip() {
    if ! command -v pip3 &>/dev/null; then
        echo -e "  ${ARROW} Installing pip3..."
        case "$PKG_MANAGER" in
            apt)    apt-get install -y -qq python3-pip >/dev/null 2>&1 ;;
            yum)    yum install -y -q python3-pip >/dev/null 2>&1 ;;
            dnf)    dnf install -y -q python3-pip >/dev/null 2>&1 ;;
            zypper) zypper --non-interactive --quiet install python3-pip >/dev/null 2>&1 ;;
        esac
    fi

    pip3 install --quiet "ansible-core>=${ANSIBLE_MIN_VERSION}"

    if ! check_ansible_version; then
        log_error "Failed to install Ansible >= $ANSIBLE_MIN_VERSION"
        exit 1
    fi
}

if ! check_ansible_version; then
    install_ansible
fi

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 4: Download/Clone Repository
# ═══════════════════════════════════════════════════════════════════════════════
step "Preparing project files"

download_repo() {
    # Tier 1: Check if already exists locally
    if [ -f "$INSTALL_DIR/site.yml" ]; then
        log_info "Using existing installation at ${BOLD}${INSTALL_DIR}${RESET}"
        return 0
    fi

    # Tier 2: git clone (shallow)
    if command -v git &>/dev/null; then
        echo -e "  ${ARROW} Cloning repository via git..."
        if git clone --depth 1 --branch "$REPO_BRANCH" "$REPO_URL" "$INSTALL_DIR" >/dev/null 2>&1; then
            log_info "Repository cloned to ${BOLD}${INSTALL_DIR}${RESET}"
            return 0
        else
            log_warn "git clone failed, trying tarball fallback..."
        fi
    else
        echo -e "  ${ARROW} git not found, downloading tarball..."
    fi

    # Tier 3: Download tarball via curl/wget
    local tarball_url="${REPO_URL%.git}/archive/refs/heads/${REPO_BRANCH}.tar.gz"
    local tmp_tarball="/tmp/newrelic-squid-proxy.tar.gz"

    if command -v curl &>/dev/null; then
        curl -sSL -o "$tmp_tarball" "$tarball_url"
    elif command -v wget &>/dev/null; then
        wget -q -O "$tmp_tarball" "$tarball_url"
    else
        log_error "Neither git, curl, nor wget is available."
        exit 1
    fi

    mkdir -p "$INSTALL_DIR"
    tar xzf "$tmp_tarball" -C /tmp/
    local extracted_dir
    extracted_dir=$(find /tmp -maxdepth 1 -type d -name "newrelic-squid-proxy-*" | head -1)

    if [ -z "$extracted_dir" ]; then
        log_error "Failed to extract tarball."
        rm -f "$tmp_tarball"
        exit 1
    fi

    cp -r "$extracted_dir"/* "$INSTALL_DIR/"
    rm -rf "$extracted_dir" "$tmp_tarball"
    log_info "Repository extracted to ${BOLD}${INSTALL_DIR}${RESET}"
}

download_repo

if [ ! -f "$INSTALL_DIR/site.yml" ]; then
    log_error "Download failed — $INSTALL_DIR/site.yml not found."
    exit 1
fi

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 5: Interactive Configuration
# ═══════════════════════════════════════════════════════════════════════════════
step "Configuring Squid Proxy"

# Initialize all variables (prevents unbound variable errors with set -u)
SQUID_PORT=""
SSL_BUMP_INPUT=""
SSL_BUMP_ENABLED="false"
SSL_BUMP_CERT_PATH=""
SSL_BUMP_KEY_PATH=""
AUTH_INPUT=""
BASIC_AUTH_ENABLED="false"
BASIC_AUTH_USERNAME=""
BASIC_AUTH_PASSWORD=""
CACHE_PEER_ENABLED="false"
CACHE_PEER_HOST=""
CACHE_PEER_PORT=""

echo ""
echo -e "  ${GRAY}Answer the following prompts to configure your proxy.${RESET}"
echo -e "  ${GRAY}Press Enter to accept defaults shown in [brackets].${RESET}"
echo ""

# All reads use /dev/tty so they work when piped via: curl | bash
prompt "${BOLD}Proxy port${RESET} ${GRAY}[3128]${RESET}: "
read -r SQUID_PORT < /dev/tty
SQUID_PORT="${SQUID_PORT:-3128}"

echo ""
prompt "${BOLD}Enable SSL Bump (MITM)?${RESET} ${GRAY}[y/N]${RESET}: "
read -r SSL_BUMP_INPUT < /dev/tty

if [[ "$SSL_BUMP_INPUT" =~ ^[Yy]$ ]]; then
    SSL_BUMP_ENABLED="true"

    prompt "  Path to CA certificate: "
    read -r SSL_BUMP_CERT_PATH < /dev/tty
    if [ ! -f "$SSL_BUMP_CERT_PATH" ]; then
        log_error "CA certificate not found: $SSL_BUMP_CERT_PATH"
        exit 1
    fi

    prompt "  Path to CA private key: "
    read -r SSL_BUMP_KEY_PATH < /dev/tty
    if [ ! -f "$SSL_BUMP_KEY_PATH" ]; then
        log_error "CA private key not found: $SSL_BUMP_KEY_PATH"
        exit 1
    fi
fi

echo ""
prompt "${BOLD}Enable Basic Auth?${RESET} ${GRAY}[y/N]${RESET}: "
read -r AUTH_INPUT < /dev/tty

if [[ "$AUTH_INPUT" =~ ^[Yy]$ ]]; then
    BASIC_AUTH_ENABLED="true"

    prompt "  Username: "
    read -r BASIC_AUTH_USERNAME < /dev/tty
    if [ -z "$BASIC_AUTH_USERNAME" ]; then
        log_error "Username cannot be empty."
        exit 1
    fi

    prompt "  Password: "
    read -sr BASIC_AUTH_PASSWORD < /dev/tty
    echo ""
    if [ -z "$BASIC_AUTH_PASSWORD" ]; then
        log_error "Password cannot be empty."
        exit 1
    fi
fi

echo ""
echo -e "  ${GRAY}  ${DIM}Enable if outbound traffic must go through a corporate proxy.${RESET}"
prompt "${BOLD}Enable Corporate Proxy Chaining (Cache Peer)?${RESET} ${GRAY}[y/N]${RESET}: "
read -r CACHE_PEER_INPUT < /dev/tty

if [[ "$CACHE_PEER_INPUT" =~ ^[Yy]$ ]]; then
    CACHE_PEER_ENABLED="true"

    prompt "  Corporate proxy host ${GRAY}(e.g. proxy.company.com)${RESET}: "
    read -r CACHE_PEER_HOST < /dev/tty
    if [ -z "$CACHE_PEER_HOST" ]; then
        log_error "Proxy host cannot be empty."
        exit 1
    fi

    prompt "  Corporate proxy port ${GRAY}[8080]${RESET}: "
    read -r CACHE_PEER_PORT < /dev/tty
    CACHE_PEER_PORT="${CACHE_PEER_PORT:-8080}"
fi

# ─── Confirmation Summary ────────────────────────────────────────────────────
echo ""
separator
echo ""
echo -e "  ${BOLD}${WHITE}  CONFIGURATION SUMMARY${RESET}"
echo ""
echo -e "  ${DOT}  OS              ${BOLD}${OS_ID} ${OS_VERSION}${RESET}"
echo -e "  ${DOT}  Proxy Port      ${BOLD}${SQUID_PORT}${RESET}"

if [ "$SSL_BUMP_ENABLED" = "true" ]; then
    echo -e "  ${DOT}  SSL Bump        ${GREEN}${BOLD}ENABLED${RESET}"
    echo -e "  ${DOT}    CA Cert       ${DIM}${SSL_BUMP_CERT_PATH}${RESET}"
    echo -e "  ${DOT}    CA Key        ${DIM}${SSL_BUMP_KEY_PATH}${RESET}"
else
    echo -e "  ${DOT}  SSL Bump        ${DIM}disabled${RESET}"
fi

if [ "$BASIC_AUTH_ENABLED" = "true" ]; then
    echo -e "  ${DOT}  Basic Auth      ${GREEN}${BOLD}ENABLED${RESET} ${GRAY}(user: ${BASIC_AUTH_USERNAME})${RESET}"
else
    echo -e "  ${DOT}  Basic Auth      ${DIM}disabled${RESET}"
fi

if [ "$CACHE_PEER_ENABLED" = "true" ]; then
    echo -e "  ${DOT}  Cache Peer      ${GREEN}${BOLD}ENABLED${RESET} ${GRAY}(${CACHE_PEER_HOST}:${CACHE_PEER_PORT})${RESET}"
else
    echo -e "  ${DOT}  Cache Peer      ${DIM}disabled${RESET}"
fi

echo ""
separator
echo ""
PROCEED=""
prompt "${BOLD}Proceed with installation?${RESET} ${GRAY}[Y/n]${RESET}: "
read -r PROCEED < /dev/tty
echo ""

if [[ "$PROCEED" =~ ^[Nn]$ ]]; then
    log_warn "Installation cancelled."
    exit 0
fi

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 6: Run Ansible Playbooks
# ═══════════════════════════════════════════════════════════════════════════════
step "Installing & configuring Squid"

# 6. Generate Ansible variables (JSON untuk extra-vars)
print_step "Generating configuration..."

# Deteksi SELinux status (jika default enforcing di RedHat)
SQUID_SELINUX_ENABLED="false"
if [[ "$OS_FAMILY" == "rhel" ]]; then
    if command -v getenforce >/dev/null 2>&1; then
        SELINUX_STATUS=$(getenforce)
        if [[ "$SELINUX_STATUS" == "Enforcing" || "$SELINUX_STATUS" == "Permissive" ]]; then
            SQUID_SELINUX_ENABLED="true"
        fi
    fi
fi

cat <<EOF > /tmp/nr-squid-vars.json
{
  "squid_port": ${SQUID_PORT},
  "ssl_bump_enabled": ${SSL_BUMP_ENABLED},
  "ssl_bump_cert_path": "${SSL_BUMP_CERT_PATH}",
  "ssl_bump_key_path": "${SSL_BUMP_KEY_PATH}",
  "basic_auth_enabled": ${BASIC_AUTH_ENABLED},
  "basic_auth_username": "${BASIC_AUTH_USERNAME}",
  "basic_auth_password": "${BASIC_AUTH_PASSWORD}",
  "cache_peer_enabled": ${CACHE_PEER_ENABLED},
  "cache_peer_host": "${CACHE_PEER_HOST}",
  "cache_peer_port": "${CACHE_PEER_PORT}",
  "squid_selinux_enabled": ${SQUID_SELINUX_ENABLED}
}
EOF

echo -e "  ${ARROW} Running installation playbook..."
echo ""

cd "$INSTALL_DIR"
ansible-playbook site.yml --extra-vars "@${VARS_FILE}"

if [ $? -ne 0 ]; then
    log_error "Installation playbook failed!"
    rm -f "$VARS_FILE"
    exit 1
fi

echo ""
log_info "Installation complete"

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 7: Verification
# ═══════════════════════════════════════════════════════════════════════════════
step "Running verification tests"

echo -e "  ${ARROW} Testing connectivity to New Relic endpoints..."
echo ""

ansible-playbook verify.yml --extra-vars "@${VARS_FILE}"

VERIFY_EXIT=$?

# Cleanup
rm -f "$VARS_FILE"

# ═══════════════════════════════════════════════════════════════════════════════
# Final Summary
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo ""

if [ $VERIFY_EXIT -eq 0 ]; then
    echo -e "${BOLD}${GREEN}"
    echo "  ╔═══════════════════════════════════════════════════════════╗"
    echo "  ║                                                           ║"
    echo "  ║        ✔  Installation Successful!                        ║"
    echo "  ║                                                           ║"
    echo "  ╚═══════════════════════════════════════════════════════════╝"
    echo -e "${RESET}"
else
    echo -e "${BOLD}${YELLOW}"
    echo "  ╔═══════════════════════════════════════════════════════════╗"
    echo "  ║                                                           ║"
    echo "  ║        ⚠  Installed with Warnings                         ║"
    echo "  ║        Some verification tests failed                     ║"
    echo "  ║                                                           ║"
    echo "  ╚═══════════════════════════════════════════════════════════╝"
    echo -e "${RESET}"
fi

echo -e "  ${BOLD}Proxy Details${RESET}"
separator
echo -e "  ${DOT}  Listen address  ${BOLD}0.0.0.0:${SQUID_PORT}${RESET}"

if [ "$SSL_BUMP_ENABLED" = "true" ]; then
    echo -e "  ${DOT}  SSL Bump port   ${BOLD}0.0.0.0:3129${RESET}"
fi

if [ "$BASIC_AUTH_ENABLED" = "true" ]; then
    echo -e "  ${DOT}  Authentication  ${BOLD}${BASIC_AUTH_USERNAME}${RESET} ${GRAY}(Basic Auth)${RESET}"
fi

echo -e "  ${DOT}  Config file     ${DIM}/etc/squid/squid.conf${RESET}"
echo -e "  ${DOT}  Install dir     ${DIM}${INSTALL_DIR}${RESET}"
echo ""

echo -e "  ${BOLD}Quick Start${RESET}"
separator

if [ "$BASIC_AUTH_ENABLED" = "true" ]; then
    echo -e "  ${GRAY}# Set proxy environment variable${RESET}"
    echo -e "  ${GREEN}export https_proxy=http://${BASIC_AUTH_USERNAME}:<password>@<host>:${SQUID_PORT}${RESET}"
    echo ""
    echo -e "  ${GRAY}# Test connection${RESET}"
    echo -e "  ${GREEN}curl -x http://${BASIC_AUTH_USERNAME}:<password>@localhost:${SQUID_PORT} https://newrelic.com${RESET}"
else
    echo -e "  ${GRAY}# Set proxy environment variable${RESET}"
    echo -e "  ${GREEN}export https_proxy=http://<host>:${SQUID_PORT}${RESET}"
    echo ""
    echo -e "  ${GRAY}# Test connection${RESET}"
    echo -e "  ${GREEN}curl -x http://localhost:${SQUID_PORT} https://newrelic.com${RESET}"
fi

echo ""

if [ "$SSL_BUMP_ENABLED" = "true" ]; then
    echo -e "  ${BOLD}SSL Bump Usage${RESET}"
    separator
    echo -e "  ${GRAY}# Use SSL Bump port for TLS interception${RESET}"
    echo -e "  ${GREEN}export https_proxy=http://localhost:3129${RESET}"
    echo ""
fi

echo -e "  ${BOLD}Management${RESET}"
separator
echo -e "  ${GRAY}# Re-run installation${RESET}"
echo -e "  ${GREEN}cd ${INSTALL_DIR} && ansible-playbook site.yml --extra-vars @vars.json${RESET}"
echo ""
echo -e "  ${GRAY}# Re-run verification only${RESET}"
echo -e "  ${GREEN}cd ${INSTALL_DIR} && ansible-playbook verify.yml --extra-vars @vars.json${RESET}"
echo ""
echo -e "  ${GRAY}# Check Squid status${RESET}"
echo -e "  ${GREEN}systemctl status squid${RESET}"
echo ""
echo -e "  ${GRAY}# View access log${RESET}"
echo -e "  ${GREEN}tail -f /var/log/squid/access.log${RESET}"
echo ""
