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

# ─── ANSI Colors ──────────────────────────────────────────────────────────────
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
BOLD="\e[1m"
RESET="\e[0m"

# ─── Helper Functions ─────────────────────────────────────────────────────────
log_info()  { echo -e "${GREEN}[INFO]${RESET}  $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${RESET}  $1"; }
log_error() { echo -e "${RED}[ERROR]${RESET} $1"; }
log_step()  { echo -e "${BLUE}${BOLD}[STEP]${RESET}  $1"; }

banner() {
    echo -e "${BOLD}${YELLOW}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║            New Relic Squid Proxy Installer                  ║"
    echo "║                                                            ║"
    echo "║  Author : Avecena Basuni                                   ║"
    echo "║  License: MIT License                                      ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${RESET}"
}

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 1: Banner
# ═══════════════════════════════════════════════════════════════════════════════
banner

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 2: Root Check
# ═══════════════════════════════════════════════════════════════════════════════
log_step "Checking privileges..."
if [ "$(id -u)" -ne 0 ]; then
    log_error "This script must be run as root or with sudo."
    log_error "Usage: sudo bash install.sh"
    exit 1
fi
log_info "Running as root — OK."

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 3: Detect OS & Package Manager
# ═══════════════════════════════════════════════════════════════════════════════
log_step "Detecting OS and package manager..."

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
        # CentOS/RHEL 7 uses yum, 8+ uses dnf
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
        log_error "Supported: Ubuntu, Debian, CentOS, RHEL, Rocky, Alma, Fedora, SLES, openSUSE"
        exit 1
        ;;
esac

log_info "Detected OS: ${BOLD}$OS_ID $OS_VERSION${RESET} (package manager: $PKG_MANAGER)"

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 4: Install Ansible
# ═══════════════════════════════════════════════════════════════════════════════
log_step "Checking Ansible installation..."

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

    # Compare versions: returns 0 if current >= minimum
    if printf '%s\n%s' "$ANSIBLE_MIN_VERSION" "$current_version" | sort -V | head -1 | grep -q "^${ANSIBLE_MIN_VERSION}$"; then
        log_info "Ansible $current_version found (>= $ANSIBLE_MIN_VERSION) — OK."
        return 0
    else
        log_warn "Ansible $current_version found but < $ANSIBLE_MIN_VERSION. Upgrading..."
        return 1
    fi
}

install_ansible() {
    log_info "Installing Ansible via $PKG_MANAGER..."

    case "$PKG_MANAGER" in
        apt)
            apt-get update -y -qq
            apt-get install -y -qq ansible
            ;;
        yum)
            yum install -y -q epel-release 2>/dev/null || true
            yum install -y -q ansible
            ;;
        dnf)
            dnf install -y -q ansible-core
            ;;
        zypper)
            zypper --non-interactive install ansible
            ;;
    esac

    # Verify installation
    if ! check_ansible_version; then
        log_warn "Package manager install did not meet version requirement. Trying pip3..."
        install_ansible_pip
    fi
}

install_ansible_pip() {
    if ! command -v pip3 &>/dev/null; then
        log_info "Installing pip3..."
        case "$PKG_MANAGER" in
            apt)    apt-get install -y -qq python3-pip ;;
            yum)    yum install -y -q python3-pip ;;
            dnf)    dnf install -y -q python3-pip ;;
            zypper) zypper --non-interactive install python3-pip ;;
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
# STEP 5: Download/Clone Repository
# ═══════════════════════════════════════════════════════════════════════════════
log_step "Preparing project files..."

download_repo() {
    # Tier 1: Check if already exists locally
    if [ -f "$INSTALL_DIR/site.yml" ]; then
        log_info "Using existing installation at $INSTALL_DIR"
        return 0
    fi

    # Tier 2: git clone (shallow)
    if command -v git &>/dev/null; then
        log_info "Cloning repository via git..."
        if git clone --depth 1 --branch "$REPO_BRANCH" "$REPO_URL" "$INSTALL_DIR" 2>/dev/null; then
            log_info "Repository cloned to $INSTALL_DIR"
            return 0
        else
            log_warn "git clone failed, falling back to tarball..."
        fi
    else
        log_warn "git not found, falling back to tarball..."
    fi

    # Tier 3: Download tarball via curl/wget
    local tarball_url="${REPO_URL%.git}/archive/refs/heads/${REPO_BRANCH}.tar.gz"
    local tmp_tarball="/tmp/newrelic-squid-proxy.tar.gz"

    if command -v curl &>/dev/null; then
        log_info "Downloading tarball via curl..."
        curl -sSL -o "$tmp_tarball" "$tarball_url"
    elif command -v wget &>/dev/null; then
        log_info "Downloading tarball via wget..."
        wget -q -O "$tmp_tarball" "$tarball_url"
    else
        log_error "Neither git, curl, nor wget is available. Cannot download repository."
        exit 1
    fi

    # Extract tarball
    mkdir -p "$INSTALL_DIR"
    tar xzf "$tmp_tarball" -C /tmp/
    # GitHub tarballs extract to <repo>-<branch>/ directory
    local extracted_dir
    extracted_dir=$(find /tmp -maxdepth 1 -type d -name "newrelic-squid-proxy-*" | head -1)

    if [ -z "$extracted_dir" ]; then
        log_error "Failed to extract tarball."
        rm -f "$tmp_tarball"
        exit 1
    fi

    cp -r "$extracted_dir"/* "$INSTALL_DIR/"
    rm -rf "$extracted_dir" "$tmp_tarball"
    log_info "Repository extracted to $INSTALL_DIR"
}

download_repo

# Validate download
if [ ! -f "$INSTALL_DIR/site.yml" ]; then
    log_error "Download failed — $INSTALL_DIR/site.yml not found."
    exit 1
fi

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 6: Interactive Prompts
# ═══════════════════════════════════════════════════════════════════════════════
log_step "Configuring Squid Proxy..."
echo ""

# Proxy port
read -rp "$(echo -e "${BOLD}Proxy port${RESET} [default: 3128]: ")" SQUID_PORT
SQUID_PORT="${SQUID_PORT:-3128}"

# SSL Bump
read -rp "$(echo -e "${BOLD}Enable SSL Bump?${RESET} (y/n) [default: n]: ")" SSL_BUMP_INPUT
SSL_BUMP_ENABLED="false"
SSL_BUMP_CERT_PATH=""
SSL_BUMP_KEY_PATH=""

if [[ "$SSL_BUMP_INPUT" =~ ^[Yy]$ ]]; then
    SSL_BUMP_ENABLED="true"

    read -rp "  Path to CA certificate: " SSL_BUMP_CERT_PATH
    if [ ! -f "$SSL_BUMP_CERT_PATH" ]; then
        log_error "CA certificate not found: $SSL_BUMP_CERT_PATH"
        exit 1
    fi

    read -rp "  Path to CA private key: " SSL_BUMP_KEY_PATH
    if [ ! -f "$SSL_BUMP_KEY_PATH" ]; then
        log_error "CA private key not found: $SSL_BUMP_KEY_PATH"
        exit 1
    fi
fi

# Basic Auth
read -rp "$(echo -e "${BOLD}Enable Basic Auth?${RESET} (y/n) [default: n]: ")" AUTH_INPUT
BASIC_AUTH_ENABLED="false"
BASIC_AUTH_USERNAME=""
BASIC_AUTH_PASSWORD=""

if [[ "$AUTH_INPUT" =~ ^[Yy]$ ]]; then
    BASIC_AUTH_ENABLED="true"

    read -rp "  Username: " BASIC_AUTH_USERNAME
    if [ -z "$BASIC_AUTH_USERNAME" ]; then
        log_error "Username cannot be empty."
        exit 1
    fi

    read -srp "  Password: " BASIC_AUTH_PASSWORD
    echo ""  # newline after hidden input
    if [ -z "$BASIC_AUTH_PASSWORD" ]; then
        log_error "Password cannot be empty."
        exit 1
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Confirmation Summary
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}${YELLOW}╔══════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${YELLOW}║         Configuration Summary                    ║${RESET}"
echo -e "${BOLD}${YELLOW}╠══════════════════════════════════════════════════╣${RESET}"
echo -e "${BOLD}${YELLOW}║${RESET}  OS Detected  : ${BOLD}$OS_ID $OS_VERSION${RESET}"
echo -e "${BOLD}${YELLOW}║${RESET}  Proxy Port   : ${BOLD}$SQUID_PORT${RESET}"
if [ "$SSL_BUMP_ENABLED" = "true" ]; then
    echo -e "${BOLD}${YELLOW}║${RESET}  SSL Bump     : ${GREEN}enabled${RESET}"
    echo -e "${BOLD}${YELLOW}║${RESET}    CA Cert     : $SSL_BUMP_CERT_PATH"
    echo -e "${BOLD}${YELLOW}║${RESET}    CA Key      : $SSL_BUMP_KEY_PATH"
else
    echo -e "${BOLD}${YELLOW}║${RESET}  SSL Bump     : ${YELLOW}disabled${RESET}"
fi
if [ "$BASIC_AUTH_ENABLED" = "true" ]; then
    echo -e "${BOLD}${YELLOW}║${RESET}  Basic Auth   : ${GREEN}enabled${RESET} (user: $BASIC_AUTH_USERNAME)"
else
    echo -e "${BOLD}${YELLOW}║${RESET}  Basic Auth   : ${YELLOW}disabled${RESET}"
fi
echo -e "${BOLD}${YELLOW}╠══════════════════════════════════════════════════╣${RESET}"

read -rp "$(echo -e "${BOLD}${YELLOW}║${RESET}  Proceed with installation? (y/n): ")" PROCEED
echo -e "${BOLD}${YELLOW}╚══════════════════════════════════════════════════╝${RESET}"

if [[ ! "$PROCEED" =~ ^[Yy]$ ]]; then
    log_warn "Installation cancelled by user."
    exit 0
fi

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 7: Generate Extra-Vars JSON
# ═══════════════════════════════════════════════════════════════════════════════
log_step "Generating configuration..."

cat > "$VARS_FILE" <<EOF
{
    "squid_port": $SQUID_PORT,
    "ssl_bump_enabled": $SSL_BUMP_ENABLED,
    "ssl_bump_cert_path": "$SSL_BUMP_CERT_PATH",
    "ssl_bump_key_path": "$SSL_BUMP_KEY_PATH",
    "basic_auth_enabled": $BASIC_AUTH_ENABLED,
    "basic_auth_username": "$BASIC_AUTH_USERNAME",
    "basic_auth_password": "$BASIC_AUTH_PASSWORD"
}
EOF

log_info "Configuration written to $VARS_FILE"

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 8: Run Ansible Playbook (site.yml)
# ═══════════════════════════════════════════════════════════════════════════════
log_step "Running installation playbook..."
echo ""

cd "$INSTALL_DIR"
ansible-playbook site.yml --extra-vars "@${VARS_FILE}"

if [ $? -ne 0 ]; then
    log_error "Installation playbook failed!"
    rm -f "$VARS_FILE"
    exit 1
fi

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 9: Run Verification Playbook (verify.yml)
# ═══════════════════════════════════════════════════════════════════════════════
log_step "Running verification playbook..."
echo ""

ansible-playbook verify.yml --extra-vars "@${VARS_FILE}"

VERIFY_EXIT=$?

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 10: Cleanup
# ═══════════════════════════════════════════════════════════════════════════════
rm -f "$VARS_FILE"

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 11: Final Summary
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}${GREEN}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║       Squid Proxy Installation Complete!                    ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo -e "║${RESET}                                                            ${BOLD}${GREEN}║"
echo -e "║${RESET}  Proxy is listening on: ${BOLD}0.0.0.0:$SQUID_PORT${RESET}                      ${BOLD}${GREEN}║"

if [ "$SSL_BUMP_ENABLED" = "true" ]; then
echo -e "║${RESET}  SSL Bump port:         ${BOLD}0.0.0.0:3129${RESET}                      ${BOLD}${GREEN}║"
fi

echo -e "║${RESET}                                                            ${BOLD}${GREEN}║"
echo -e "║${RESET}  ${BOLD}Usage:${RESET}                                                    ${BOLD}${GREEN}║"

if [ "$BASIC_AUTH_ENABLED" = "true" ]; then
echo -e "║${RESET}  export https_proxy=http://${BASIC_AUTH_USERNAME}:<pass>@<host>:${SQUID_PORT}   ${BOLD}${GREEN}║"
else
echo -e "║${RESET}  export https_proxy=http://<host>:${SQUID_PORT}                    ${BOLD}${GREEN}║"
fi

echo -e "║${RESET}                                                            ${BOLD}${GREEN}║"
echo -e "║${RESET}  ${BOLD}Test:${RESET}                                                     ${BOLD}${GREEN}║"

if [ "$BASIC_AUTH_ENABLED" = "true" ]; then
echo -e "║${RESET}  curl -x http://${BASIC_AUTH_USERNAME}:<pass>@localhost:${SQUID_PORT} \\        ${BOLD}${GREEN}║"
else
echo -e "║${RESET}  curl -x http://localhost:${SQUID_PORT} \\                          ${BOLD}${GREEN}║"
fi

echo -e "║${RESET}       https://newrelic.com                                  ${BOLD}${GREEN}║"
echo -e "║${RESET}                                                            ${BOLD}${GREEN}║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${RESET}"

if [ $VERIFY_EXIT -ne 0 ]; then
    log_warn "Some verification checks failed. Review the output above."
fi
