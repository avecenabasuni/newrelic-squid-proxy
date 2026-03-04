# Test Plan: New Relic Squid Proxy

Validasi menyeluruh dari instalasi sampai teardown.
Jalankan semua command di VM target sebagai `root`.

---

## Prerequisites

```bash
# 1. Clone repo di VM
cd /root
git clone https://github.com/avecenabasuni/newrelic-squid-proxy.git
cd newrelic-squid-proxy

# 2. Install dependencies
apt update && apt install -y ansible yamllint shellcheck curl net-tools
# atau RHEL:
# yum install -y ansible yamllint ShellCheck curl net-tools
```

---

## Phase 1: Installation (Happy Path)

### 1.1 Run Installer

```bash
cd /root/newrelic-squid-proxy
sudo bash install.sh
```

Jawab prompt dengan konfigurasi berikut:

| Prompt | Jawaban |
| ------ | ------- |
| Proxy Port | `3128` (default) |
| NR Region | `us` |
| Enable SSL Bump? | `n` |
| Enable Basic Auth? | `n` |
| Enable Cache Peer? | `n` |
| Enable NR Integration? | `y` |
| Proceed? | `Y` |

**Expected:** Ansible playbook berjalan sampai selesai tanpa error merah.

---

## Phase 2: Automated Verification (Core Tests)

Kami telah menyediakan script E2E otomatis untuk menguji konfigurasi, runtime, dan connectivity New Relic.
Jalankan script ini:

```bash
cd /root/newrelic-squid-proxy
sudo bash test.sh
```

**Expected:** Script akan memvalidasi linting, runtime Squid, port binding, HTTP tunneling API, domain blocking, dan integrasi NR Infra. Semua baris harus menunjukkan `[PASS]`.

---

## Phase 3: Feature-Specific Tests

### 3.1 SSL Bump (M5) - Optional

Hanya jika install ulang dengan SSL Bump enabled:

```bash
# Re-install with SSL Bump auto-generate
sudo bash install.sh
# Jawab Y untuk SSL Bump, pilih auto-generate

# Verifikasi CA cert exists
ls -la /etc/squid/ssl_cert/proxy-ca.pem
ls -la /etc/squid/ssl_cert/proxy-ca.key
# Expected: file ada, permission 0644 (cert) dan 0600 (key)

# Verifikasi SSL DB
ls -la /var/lib/squid/ssl_db/
# Expected: directory ada dan berisi file

# Test manual CA rotation
sudo /usr/local/bin/rotate-squid-ca.sh
# Expected: backup dibuat, CA baru digenerate, squid restart sukses

# Verifikasi cron job terdaftar
crontab -l | grep rotate-squid-ca
# Expected: ada entry "0 3 * * * /usr/local/bin/rotate-squid-ca.sh"
```

### 3.2 Basic Auth - Optional

Hanya jika install ulang dengan Basic Auth enabled:

```bash
# Re-install with Basic Auth
sudo bash install.sh
# Jawab Y untuk Basic Auth, masukkan user/password

# Tanpa credential -> DENIED
curl -s -o /dev/null -w "%{http_code}" -x http://localhost:3128 https://log-api.newrelic.com/log/v1
# Expected: 407 (Proxy Authentication Required)

# Dengan credential -> ALLOWED
curl -s -o /dev/null -w "%{http_code}" -x http://user:password@localhost:3128 https://log-api.newrelic.com/log/v1
# Expected: 200 (Connection established)
```

### 3.3 Firewall Auto-Open (N2)

```bash
# Cek apakah port sudah dibuka
# UFW:
ufw status | grep 3128
# atau Firewalld:
firewall-cmd --list-ports | grep 3128
# atau iptables:
iptables -L -n | grep 3128
# Expected: port 3128 terbuka untuk TCP
```

---

## Phase 4: Uninstall & Rollback

### 4.1 Run Uninstaller

```bash
cd /root/newrelic-squid-proxy
sudo bash uninstall.sh
# Jawab Y untuk konfirmasi
# Jawab Y untuk hapus installer directory (optional)
```

### 5.2 Verifikasi Clean State

```bash
# Service harus sudah mati
systemctl status squid 2>&1
# Expected: "Unit squid.service could not be found" atau inactive

# Port tidak lagi listening
ss -tulpn | grep 3128
# Expected: tidak ada output

# Semua file konfigurasi dihapus
ls /etc/squid 2>&1
# Expected: "No such file or directory"

ls /var/log/squid 2>&1
# Expected: "No such file or directory"

ls /var/lib/squid 2>&1
# Expected: "No such file or directory"

ls /var/spool/squid 2>&1
# Expected: "No such file or directory"

# NR integration configs dihapus
ls /etc/newrelic-infra/logging.d/squid.yml 2>&1
# Expected: "No such file or directory"

ls /etc/newrelic-infra/integrations.d/squid-metrics.yml 2>&1
# Expected: "No such file or directory"

# CA rotation script dihapus
ls /usr/local/bin/rotate-squid-ca.sh 2>&1
# Expected: "No such file or directory"

# Cron job dihapus
crontab -l 2>&1 | grep rotate-squid-ca
# Expected: tidak ada output

# Temp files dihapus
ls /tmp/nr-squid-vars.json 2>&1
# Expected: "No such file or directory"
```

### 5.3 Idempotency: Re-install dari Nol

```bash
# Install ulang dari clean state
cd /root/newrelic-squid-proxy
sudo bash install.sh
# Jawab prompt seperti Phase 2

# Verifikasi squid berjalan kembali
systemctl status squid
ss -tulpn | grep 3128
squid -k parse
# Expected: semua sukses, sama seperti Phase 2
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
