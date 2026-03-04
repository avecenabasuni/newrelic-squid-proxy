#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# New Relic Squid Proxy — E2E Testing Script
# Automated test suite for validating installation & connectivity.
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# UI Colors
GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
CYAN="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

pass() { echo -e "  ${GREEN}✔ [PASS]${RESET} $1"; }
fail() { echo -e "  ${RED}✘ [FAIL]${RESET} $1"; exit 1; }
warn() { echo -e "  ${YELLOW}⚠ [WARN]${RESET} $1"; }
step() { echo -e "\n${BOLD}${CYAN}▶ $1${RESET}"; }

# Check root
if [[ "$EUID" -ne 0 ]]; then
    echo -e "${RED}ERROR: This script must be run as root (sudo).${RESET}"
    exit 1
fi

echo -e "${BOLD}Running E2E Validation Tests for New Relic Squid Proxy${RESET}"

# ──────────────────────────────────────────────────────────────────────────────
step "Phase 1: Linting & Syntax Checks"

if command -v yamllint &>/dev/null; then
    if yamllint -d relaxed . > /dev/null 2>&1; then
        pass "yamllint passed"
    else
        warn "yamllint has warnings/errors (run manually to inspect)"
    fi
else
    warn "yamllint not installed, skipping..."
fi

if command -v ansible-lint &>/dev/null; then
    if ansible-lint site.yml > /dev/null 2>&1; then
        pass "ansible-lint passed"
    else
        warn "ansible-lint has warnings/errors (run manually to inspect)"
    fi
else
    warn "ansible-lint not installed, skipping..."
fi

if command -v shellcheck &>/dev/null; then
    if shellcheck install.sh uninstall.sh support-bundle.sh test.sh > /dev/null 2>&1; then
        pass "shellcheck passed"
    else
        warn "shellcheck has warnings/errors (run manually to inspect)"
    fi
else
    warn "shellcheck not installed, skipping..."
fi

if ansible-playbook site.yml --syntax-check > /dev/null 2>&1; then
    pass "Ansible syntax check passed"
else
    fail "Ansible syntax check failed!"
fi

# ──────────────────────────────────────────────────────────────────────────────
step "Phase 2: Squid Configuration & Runtime"

SQUID_PORT=$(grep -E '^http_port ' /etc/squid/squid.conf 2>/dev/null | awk '{print $2}' || echo "3128")
PROXY_ARG="-x http://localhost:${SQUID_PORT}"

if squid -k parse > /dev/null 2>&1; then
    pass "squid.conf syntax is valid"
else
    fail "squid.conf syntax is invalid (run 'squid -k parse' to see why)"
fi

if systemctl is-active --quiet squid; then
    pass "squid service is running"
else
    fail "squid service is NOT running"
fi

if ss -tulpn | grep -q ":${SQUID_PORT}"; then
    pass "squid is listening on port ${SQUID_PORT}"
else
    fail "squid is NOT listening on port ${SQUID_PORT}"
fi

# ──────────────────────────────────────────────────────────────────────────────
step "Phase 3: E2E Connectivity (New Relic Endpoints)"

# Test 1: Log API
echo "  Testing connection to Log API (US)..."
HTTP_CODE=$(curl "$PROXY_ARG" -s -o /dev/null -w "%{http_code}" https://log-api.newrelic.com --connect-timeout 5 || echo "000")
if [[ "$HTTP_CODE" == "202" || "$HTTP_CODE" == "403" || "$HTTP_CODE" == "200" || "$HTTP_CODE" == "404" ]]; then
    pass "Connection to US Log API established through proxy (HTTP $HTTP_CODE)"
else
    fail "Failed to connect to US Log API through proxy (HTTP $HTTP_CODE)"
fi

# Test 2: Blocked Domains
echo "  Testing non-New Relic domain blocking..."
HTTP_CODE_BLOCKED=$(curl "$PROXY_ARG" -s -o /dev/null -w "%{http_code}" https://www.google.com --connect-timeout 5 || echo "000")
if [[ "$HTTP_CODE_BLOCKED" == "403" ]]; then
    pass "Proxy correctly BLOCKS non-New Relic domains (google.com -> 403 Access Denied)"
else
    fail "Proxy FAILED to block non-New Relic domain (Got HTTP $HTTP_CODE_BLOCKED)"
fi

# ──────────────────────────────────────────────────────────────────────────────
step "Phase 4: NR Infrastructure Integration Checks"

if curl -s "http://localhost:${SQUID_PORT}/squid-internal-mgr/counters" --connect-timeout 2 | grep -q 'client_http.requests'; then
    pass "Cache Manager API (/counters) is accessible from localhost"
else
    warn "Cache Manager API (/counters) is NOT accessible (Skipped if NR Integration disabled)"
fi

if [ -f "/etc/newrelic-infra/logging.d/squid.yml" ] && [ -f "/etc/newrelic-infra/integrations.d/squid-metrics.yml" ]; then
    pass "New Relic Infrastructure agent config files are deployed"
else
    warn "New Relic Infrastructure agent config files are MISSING (Skipped if disabled)"
fi

# ──────────────────────────────────────────────────────────────────────────────
echo -e "\n${BOLD}${GREEN}🎉 ALL CORE TESTS PASSED!${RESET}"
echo -e "Refer to test-plan.md for optional feature-specific testing (SSL Bump, Auth, Uninstall).\n"
