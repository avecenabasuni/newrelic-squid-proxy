#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# New Relic Squid Proxy — Diagnostic Support Bundle
# Author : Avecena Basuni
# License: MIT License
#
# Generates a .tar.gz archive containing Squid configs, logs, OS state,
# and New Relic connectivity tests for troubleshooting purposes.
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# Require root
if [[ "$EUID" -ne 0 ]]; then
    echo "ERROR: This script must be run as root (sudo)."
    exit 1
fi

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
HOSTNAME=$(hostname -s)
BUNDLE_DIR="/tmp/nr-squid-support-${HOSTNAME}-${TIMESTAMP}"
TARBALL="/tmp/nr-squid-support-${HOSTNAME}-${TIMESTAMP}.tar.gz"

echo -e "\e[1m\e[36mGenerating Support Bundle for New Relic Squid Proxy...\e[0m"
echo "Creating temporary directory: $BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR"

# ─── 1. System Info ────────────────────────────────────────────────────────
echo "  ▸ Collecting System Info..."
uname -a > "$BUNDLE_DIR/uname.txt"
cat /etc/os-release > "$BUNDLE_DIR/os-release.txt"
date -R > "$BUNDLE_DIR/date.txt"
uptime > "$BUNDLE_DIR/uptime.txt"
df -h > "$BUNDLE_DIR/df.txt"
free -m > "$BUNDLE_DIR/free.txt"

# ─── 2. Squid Process & Version ────────────────────────────────────────────
echo "  ▸ Collecting Squid Installation State..."
if command -v squid &>/dev/null; then
    squid -v > "$BUNDLE_DIR/squid-version.txt" 2>&1
else
    echo "squid binary not found in PATH" > "$BUNDLE_DIR/squid-version.txt"
fi

systemctl status squid --no-pager -l > "$BUNDLE_DIR/systemctl-status-squid.txt" 2>&1 || true
journalctl -u squid -n 500 --no-pager > "$BUNDLE_DIR/journalctl-squid.txt" 2>&1 || true

# ─── 3. Squid Configuration ────────────────────────────────────────────────
echo "  ▸ Collecting Configuration (masking passwords)..."
mkdir -p "$BUNDLE_DIR/etc-squid"
if [ -d "/etc/squid" ]; then
    # Copy config but mask auth passwords if present
    cp -r /etc/squid/* "$BUNDLE_DIR/etc-squid/" 2>/dev/null || true
    if [ -f "$BUNDLE_DIR/etc-squid/passwords" ]; then
        sed -i 's/:.*/:<MASKED>/g' "$BUNDLE_DIR/etc-squid/passwords"
    fi
    # Also mask cache_peer password if any user added it manually
    if [ -f "$BUNDLE_DIR/etc-squid/squid.conf" ]; then
        sed -i -E 's/(cache_peer .* login=[^:]*:)([^ ]*)(.*)/\1<MASKED>\3/g' "$BUNDLE_DIR/etc-squid/squid.conf"
    fi
fi

# ─── 4. Squid Logs ─────────────────────────────────────────────────────────
echo "  ▸ Collecting Logs (last 1000 lines)..."
mkdir -p "$BUNDLE_DIR/var-log-squid"
if [ -d "/var/log/squid" ]; then
    if [ -f "/var/log/squid/cache.log" ]; then
        tail -n 1000 /var/log/squid/cache.log > "$BUNDLE_DIR/var-log-squid/cache.log"
    fi
    if [ -f "/var/log/squid/access.log" ]; then
        tail -n 1000 /var/log/squid/access.log > "$BUNDLE_DIR/var-log-squid/access.log"
    fi
fi

# ─── 5. Network & Firewall ─────────────────────────────────────────────────
echo "  ▸ Collecting Network State..."
if command -v ss &>/dev/null; then
    ss -tlpn > "$BUNDLE_DIR/ss-tlpn.txt"
elif command -v netstat &>/dev/null; then
    netstat -tlpn > "$BUNDLE_DIR/netstat-tlpn.txt"
fi

if command -v ufw &>/dev/null; then
    ufw status verbose > "$BUNDLE_DIR/firewall.txt" 2>&1 || true
elif command -v firewall-cmd &>/dev/null; then
    firewall-cmd --list-all > "$BUNDLE_DIR/firewall.txt" 2>&1 || true
elif command -v iptables &>/dev/null; then
    iptables -L -n -v > "$BUNDLE_DIR/firewall.txt" 2>&1 || true
fi

# SELinux check
if command -v sestatus &>/dev/null; then
    sestatus > "$BUNDLE_DIR/selinux.txt"
fi

# ─── 6. New Relic Connectivity Test ────────────────────────────────────────
echo "  ▸ Running New Relic Connectivity Test..."
echo "Connectivity Test from proxy host to NR Endpoints" > "$BUNDLE_DIR/nr-connectivity.txt"
echo "------------------------------------------------" >> "$BUNDLE_DIR/nr-connectivity.txt"

SQUID_PORT=$(grep -E '^http_port ' /etc/squid/squid.conf 2>/dev/null | awk '{print $2}' || echo "3128")
PROXY_ARG="-x http://localhost:${SQUID_PORT}"

# Test without proxy (direct)
echo "1. DIRECT INTERNET ACCESS (No Proxy)" >> "$BUNDLE_DIR/nr-connectivity.txt"
curl -s -o /dev/null -w "%{http_code}" https://infra-api.newrelic.com --connect-timeout 5 >> "$BUNDLE_DIR/nr-connectivity.txt" 2>&1 || echo "FAILED" >> "$BUNDLE_DIR/nr-connectivity.txt"
echo -e "\n" >> "$BUNDLE_DIR/nr-connectivity.txt"

# Test via Squid local
echo "2. VIA LOCAL SQUID PROXY (Port ${SQUID_PORT})" >> "$BUNDLE_DIR/nr-connectivity.txt"
curl $PROXY_ARG -s -o /dev/null -w "%{http_code}" https://infra-api.newrelic.com --connect-timeout 5 >> "$BUNDLE_DIR/nr-connectivity.txt" 2>&1 || echo "FAILED" >> "$BUNDLE_DIR/nr-connectivity.txt"
echo -e "\n" >> "$BUNDLE_DIR/nr-connectivity.txt"

# ─── 7. Archive & Cleanup ──────────────────────────────────────────────────
echo "  ▸ Archiving Bundle..."
tar -czf "$TARBALL" -C /tmp "$(basename "$BUNDLE_DIR")"
rm -rf "$BUNDLE_DIR"

echo -e "\n\e[1m\e[32m✔ Support bundle created successfully!\e[0m"
echo -e "\e[1mPlease share this file with New Relic Support:\e[0m"
echo -e "\e[33m  $TARBALL\e[0m\n"
