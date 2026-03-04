# Test Plan: New Relic Squid Proxy

Comprehensive validation from installation to teardown.
Run all commands on the target VM as `root`.

---

## Prerequisites

```bash
# 1. Clone repo on VM
cd /root
git clone https://github.com/avecenabasuni/newrelic-squid-proxy.git
cd newrelic-squid-proxy

# 2. Install dependencies
apt update && apt install -y ansible yamllint shellcheck curl net-tools
# or RHEL:
# yum install -y ansible yamllint ShellCheck curl net-tools
```

---

## Phase 1: Installation (Happy Path)

### 1.1 Run Installer

```bash
cd /root/newrelic-squid-proxy
sudo bash install.sh
```

Respond to the prompts with the following configuration:

| Prompt | Answer |
| ------ | ------- |
| Proxy Port | `3128` (default) |
| NR Region | `us` |
| Enable SSL Bump? | `n` |
| Enable Basic Auth? | `n` |
| Enable Cache Peer? | `n` |
| Enable NR Integration? | `y` |
| Proceed? | `Y` |

**Expected:** Ansible playbook runs to completion without red errors.

---

## Phase 2: Automated Verification (Core Tests)

An automated E2E script is provided to test configuration, runtime, and New Relic connectivity.
Run this script:

```bash
cd /root/newrelic-squid-proxy
sudo bash test.sh
```

**Expected:** The script will validate linting, Squid runtime, port binding, HTTP tunneling API, domain blocking, and NR Infra integration. All lines should show `[PASS]`.

---

## Phase 3: Feature-Specific Tests

### 3.1 SSL Bump (M5) - Optional

Only if re-installing with SSL Bump enabled:

```bash
# Re-install with SSL Bump auto-generate
sudo bash install.sh
# Answer Y for SSL Bump, choose auto-generate

# Verify CA cert exists
ls -la /etc/squid/ssl_cert/proxy-ca.pem
ls -la /etc/squid/ssl_cert/proxy-ca.key
# Expected: files exist, permissions 0644 (cert) and 0600 (key)

# Verify SSL DB
ls -la /var/lib/squid/ssl_db/
# Expected: directory exists and contains files

# Test manual CA rotation
sudo /usr/local/bin/rotate-squid-ca.sh
# Expected: backup created, new CA generated, squid restart successful

# Verify cron job is registered
crontab -l | grep rotate-squid-ca
# Expected: entry found "0 3 * * * /usr/local/bin/rotate-squid-ca.sh"
```

### 3.2 Basic Auth - Optional

Only if re-installing with Basic Auth enabled:

```bash
# Re-install with Basic Auth
sudo bash install.sh
# Answer Y for Basic Auth, enter user/password

# Without credentials -> DENIED
curl -s -o /dev/null -w "%{http_code}" -x http://localhost:3128 https://log-api.newrelic.com/log/v1
# Expected: 407 (Proxy Authentication Required)

# With credentials -> ALLOWED
curl -s -o /dev/null -w "%{http_code}" -x http://user:password@localhost:3128 https://log-api.newrelic.com/log/v1
# Expected: 200 (Connection established)
```

### 3.3 Firewall Auto-Open (N2)

```bash
# Check if port is opened
# UFW:
ufw status | grep 3128
# or Firewalld:
firewall-cmd --list-ports | grep 3128
# or iptables:
iptables -L -n | grep 3128
# Expected: port 3128 open for TCP
```

---

## Phase 4: Uninstall & Rollback

### 4.1 Run Uninstaller

```bash
cd /root/newrelic-squid-proxy
sudo bash uninstall.sh
# Answer Y for confirmation
# Answer Y to remove installer directory (optional)
```

### 5.2 Verify Clean State

```bash
# Service must be dead
systemctl status squid 2>&1
# Expected: "Unit squid.service could not be found" or inactive

# Port no longer listening
ss -tulpn | grep 3128
# Expected: no output

# All configuration files removed
ls /etc/squid 2>&1
# Expected: "No such file or directory"

ls /var/log/squid 2>&1
# Expected: "No such file or directory"

ls /var/lib/squid 2>&1
# Expected: "No such file or directory"

ls /var/spool/squid 2>&1
# Expected: "No such file or directory"

# NR integration configs removed
ls /etc/newrelic-infra/logging.d/squid.yml 2>&1
# Expected: "No such file or directory"

ls /etc/newrelic-infra/integrations.d/squid-metrics.yml 2>&1
# Expected: "No such file or directory"

# CA rotation script removed
ls /usr/local/bin/rotate-squid-ca.sh 2>&1
# Expected: "No such file or directory"

# Cron job removed
crontab -l 2>&1 | grep rotate-squid-ca
# Expected: no output

# Temp files removed
ls /tmp/nr-squid-vars.json 2>&1
# Expected: "No such file or directory"
```

### 5.3 Idempotency: Re-install from Scratch

```bash
# Re-install from clean state
cd /root/newrelic-squid-proxy
sudo bash install.sh
# Answer prompts as in Phase 2

# Verify squid is running again
systemctl status squid
ss -tulpn | grep 3128
squid -k parse
# Expected: all success, same as Phase 2
```

---

## Checklist Summary

| # | Test | Status |
| --- | ------ | -------- |
| 1.1 | Linting (yamllint, ansible-lint, shellcheck) | [ ] |
| 1.2 | Ansible Syntax Check | [ ] |
| 2.1 | Install Happy Path | [ ] |
| 2.2 | Service Running | [ ] |
| 2.3 | Config Files Exist | [ ] |
| 3.1 | Proxy to NR US | [ ] |
| 3.2 | Blocked Domains | [ ] |
| 3.3 | Manager Metrics /counters | [ ] |
| 3.4 | NR Infra Agent Integration deployed | [ ] |
| 4.1 | SSL Bump (opt) | [ ] |
| 4.2 | Basic Auth (opt) | [ ] |
| 4.3 | Firewall Open | [ ] |
| 5.1 | Uninstall | [ ] |
| 5.2 | Clean State | [ ] |
| 5.3 | Re-install | [ ] |
