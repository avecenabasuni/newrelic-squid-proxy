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

## Phase 1: Static Analysis & Linting

### 1.1 YAML Lint

```bash
yamllint -d relaxed site.yml teardown.yml verify.yml \
  roles/squid_proxy/defaults/main.yml \
  roles/squid_proxy/tasks/*.yml \
  roles/squid_proxy/vars/*.yml \
  roles/squid_proxy/handlers/main.yml
```

**Expected:** Tidak ada error (warning boleh).

### 1.2 ShellCheck

```bash
shellcheck install.sh uninstall.sh support-bundle.sh
```

**Expected:** Tidak ada error level `error`. Warning SC2034/SC2086 bisa di-ignore jika disengaja.

### 1.3 Ansible Lint

```bash
ansible-lint site.yml
```

**Expected:** Tidak ada critical error. Warning deprecated module bisa di-note untuk perbaikan.

### 1.4 Ansible Syntax Check

```bash
ansible-playbook site.yml --syntax-check
ansible-playbook teardown.yml --syntax-check
```

**Expected:** `playbook: site.yml` dan `playbook: teardown.yml` tanpa error.

---

## Phase 2: Installation (Happy Path)

### 2.1 Run Installer

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

### 2.2 Verifikasi Service

```bash
# Squid sedang berjalan?
systemctl status squid
# Expected: Active: active (running)

# Listening di port 3128?
ss -tulpn | grep 3128
# Expected: LISTEN 0 ... *:3128
```

### 2.3 Verifikasi File Konfigurasi

```bash
# squid.conf valid
squid -k parse
# Expected: tidak ada error

# Konfigurasi utama
ls -la /etc/squid/squid.conf
ls -la /etc/squid/allowed_domains.txt

# NR Integration configs deployed
ls -la /etc/newrelic-infra/logging.d/squid.yml
ls -la /etc/newrelic-infra/integrations.d/squid-metrics.yml
# Expected: kedua file ada (meskipun NR agent belum terinstall)
```

---

## Phase 3: E2E Connectivity

### 3.1 Proxy ke New Relic US Endpoints

```bash
# Test CONNECT tunnel ke log-api.newrelic.com
curl -v -x http://localhost:3128 https://log-api.newrelic.com/log/v1 2>&1 | head -30
# Expected: "HTTP/1.1 200 Connection established" atau respons dari NR API

# Test metric-api
curl -s -o /dev/null -w "%{http_code}" -x http://localhost:3128 https://metric-api.newrelic.com/metric/v1
# Expected: 202 atau 403 (NR rejects tanpa license key, tapi proxy CONNECT berhasil)

# Test infra-api
curl -s -o /dev/null -w "%{http_code}" -x http://localhost:3128 https://infra-api.newrelic.com
# Expected: bukan 503 (artinya domain diterima oleh ACL)
```

### 3.2 Blocked Domains

```bash
# Domain non-New Relic harus DITOLAK
curl -s -o /dev/null -w "%{http_code}" -x http://localhost:3128 https://www.google.com
# Expected: 403 (Access Denied)

curl -s -o /dev/null -w "%{http_code}" -x http://localhost:3128 https://github.com
# Expected: 403 (Access Denied)
```

### 3.3 Region-Aware Blocking (N1)

Karena `nr_region=us`, endpoint EU harus DITOLAK:

```bash
curl -s -o /dev/null -w "%{http_code}" -x http://localhost:3128 https://log-api.eu.newrelic.com/log/v1
# Expected: 403 (EU endpoint diblokir saat region=us)

curl -s -o /dev/null -w "%{http_code}" -x http://localhost:3128 https://metric-api.eu.newrelic.com/metric/v1
# Expected: 403
```

### 3.4 Manager Metrics Access (N4)

```bash
# Akses cache manager dari localhost
curl -s http://localhost:3128/squid-internal-mgr/counters | head -20
# Expected: output key=value seperti:
#   client_http.requests = 5
#   client_http.hits = 0
#   server.all.requests = 3

curl -s http://localhost:3128/squid-internal-mgr/info | head -20
# Expected: output key:value seperti:
#   Squid Object Cache: Version X.X
#   Number of clients accessing cache: 1
```

### 3.5 Access Log Verification

```bash
# Setelah semua curl di atas, cek access log
tail -20 /var/log/squid/access.log
# Expected: entry untuk setiap request (TCP_TUNNEL/200 untuk allowed, TCP_DENIED/403 untuk blocked)
```

---

## Phase 4: Feature-Specific Tests

### 4.1 SSL Bump (M5) - Optional

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

### 4.2 Basic Auth - Optional

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

### 4.3 Firewall Auto-Open (N2)

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

## Phase 5: Uninstall & Rollback

### 5.1 Run Uninstaller

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
|---|------|--------|
| 1.1 | YAML Lint | [ ] |
| 1.2 | ShellCheck | [ ] |
| 1.3 | Ansible Lint | [ ] |
| 1.4 | Syntax Check | [ ] |
| 2.1 | Install Happy Path | [ ] |
| 2.2 | Service Running | [ ] |
| 2.3 | Config Files Exist | [ ] |
| 3.1 | Proxy to NR US | [ ] |
| 3.2 | Blocked Domains | [ ] |
| 3.3 | EU Region Blocked | [ ] |
| 3.4 | Manager Metrics | [ ] |
| 3.5 | Access Logs | [ ] |
| 4.1 | SSL Bump (opt) | [ ] |
| 4.2 | Basic Auth (opt) | [ ] |
| 4.3 | Firewall Open | [ ] |
| 5.1 | Uninstall | [ ] |
| 5.2 | Clean State | [ ] |
| 5.3 | Re-install | [ ] |
