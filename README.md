# New Relic Squid Proxy

Otomasi instalasi dan konfigurasi **Squid Proxy** untuk mendukung POC New Relic di environment yang membutuhkan forward proxy.

## Fitur

- **One-liner install** - `curl -sSL <URL>/install.sh | sudo bash`
- **Multi-distro** - Ubuntu, Debian, CentOS, RHEL, Rocky, Alma, Fedora, SLES, openSUSE
- **SSL Bump (opsional)** - MITM interception untuk TLS traffic ke New Relic
- **Basic Auth (opsional)** - Autentikasi proxy via htpasswd
- **Cache Peer (opsional)** - Corporate proxy chaining untuk environment tanpa direct internet
- **Domain whitelist** - Hanya mengizinkan akses ke endpoint New Relic + OS package repos
- **Dynamic ACLs** - Domain list di file external, bisa di-reload tanpa restart (`squid -k reconfigure`)
- **Log Forwarding** - Forward `access.log` dan `cache.log` ke New Relic Logs via NR Infra Agent
- **SELinux support** - Auto-configure SELinux booleans dan contexts di RHEL-based
- **Dry-run mode** - Preview semua perubahan tanpa apply (`--dry-run`)
- **Uninstall script** - Hapus semua komponen dengan satu command
- **Support bundle** - Diagnostic archive untuk troubleshooting (`support-bundle.sh`)
- **Automated verification** - Uji koneksi ke 32+ endpoint New Relic (US + EU) otomatis
- **Idempoten** - Aman dijalankan berulang kali

## Quick Start

### Instalasi Otomatis (Recommended)

```bash
curl -sSL https://raw.githubusercontent.com/avecenabasuni/newrelic-squid-proxy/main/install.sh | sudo bash
```

Script akan otomatis:
1. Mendeteksi OS dan package manager
2. Menginstall Ansible jika belum ada
3. Menampilkan prompt konfigurasi interaktif
4. Menginstall dan mengkonfigurasi Squid Proxy
5. Menjalankan verifikasi koneksi ke semua endpoint New Relic

### Instalasi Manual

```bash
# Clone repository
git clone https://github.com/avecenabasuni/newrelic-squid-proxy.git
cd newrelic-squid-proxy

# Jalankan installer
sudo bash install.sh
```

### Dry-run (Preview Tanpa Apply)

```bash
sudo bash install.sh --dry-run
```

Ansible dijalankan dengan `--check --diff` sehingga tidak ada package yang diinstall atau config yang diubah.

### Override Repository URL

```bash
REPO_URL=https://github.com/my-fork/newrelic-squid-proxy.git bash install.sh
```

## Konfigurasi

Semua konfigurasi ditanyakan via prompt interaktif saat instalasi:

| Parameter | Default | Deskripsi |
| --------- | ------- | --------- |
| Proxy Port | `3128` | Port HTTP proxy |
| SSL Bump | `disabled` | Enable MITM interception (menyediakan CA cert eksisting atau generate auto-rotation) |
| Basic Auth | `disabled` | Enable autentikasi proxy (butuh username & password) |
| Cache Peer | `disabled` | Enable corporate proxy chaining (butuh host & port upstream proxy) |

## Penggunaan Proxy

### Tanpa Autentikasi

```bash
export https_proxy=http://<proxy-host>:3128
curl https://newrelic.com
```

### Dengan Autentikasi

```bash
export https_proxy=http://username:password@<proxy-host>:3128
curl https://newrelic.com
```

### Set Proxy untuk New Relic Agent

```bash
# Tambahkan ke environment atau konfigurasi agent
export NEW_RELIC_PROXY_HOST=<proxy-host>
export NEW_RELIC_PROXY_PORT=3128
```

## Dynamic ACL (Tambah Domain Tanpa Restart)

Domain whitelist disimpan di `/etc/squid/allowed_domains.txt`. Untuk menambah domain baru:

```bash
# Tambah domain
echo ".api.newrelic.com" >> /etc/squid/allowed_domains.txt

# Reload konfigurasi (tanpa restart, zero downtime)
squid -k reconfigure
```

## Log Forwarding ke New Relic

Untuk mengirim Squid logs ke New Relic Logs, enable saat instalasi atau set variabel:

```yaml
# group_vars/all.yml atau extra-vars
log_forwarding_enabled: true
```

Membutuhkan NR Infrastructure Agent terinstall di host yang sama. Config akan di-deploy ke `/etc/newrelic-infra/logging.d/squid.yml`.

## Uninstall

```bash
# Standalone script
sudo bash uninstall.sh

# Atau via Ansible
ansible-playbook teardown.yml
```

## Diagnostic Support Bundle

Jika ada masalah koneksi, generate diagnostic archive:

```bash
sudo bash support-bundle.sh
```

Menghasilkan file `.tar.gz` di `/tmp/` berisi:
- System info (OS, uptime, disk, memory)
- Squid version dan compile flags
- Konfigurasi Squid (password otomatis di-mask)
- 1000 baris terakhir access.log dan cache.log
- Status port, firewall, dan SELinux
- Hasil tes konektivitas ke New Relic

## Struktur Project

```text
├── install.sh                  # Bootstrap installer (interactive)
├── uninstall.sh                # Standalone uninstaller
├── support-bundle.sh           # Diagnostic archive generator
├── ansible.cfg                 # Ansible configuration
├── inventory/localhost.ini     # Localhost inventory
├── site.yml                    # Main installation playbook
├── verify.yml                  # Verification playbook
├── teardown.yml                # Uninstall playbook (Ansible)
├── roles/
│   ├── squid_proxy/            # Squid installation & configuration role
│   │   ├── defaults/main.yml   # Default variables
│   │   ├── vars/               # OS-specific variables
│   │   ├── tasks/              # Installation & configuration tasks
│   │   ├── handlers/           # Service restart & reconfigure handlers
│   │   └── templates/          # squid.conf.j2, allowed_domains.txt.j2, nr-logging.yml.j2
│   └── verify/                 # Endpoint verification role
├── legacy/                     # File konfigurasi versi lama (referensi)
├── new-feature.md              # Roadmap fitur
└── plan-squid-proxy.md         # Dokumen perencanaan
```

## Jalankan Ulang Playbook Secara Manual

```bash
cd /opt/newrelic-squid-proxy

# Install/reconfigure
ansible-playbook site.yml --extra-vars '{\"squid_port\": 3128, \"ssl_bump_enabled\": false, \"basic_auth_enabled\": false}'

# Verify
ansible-playbook verify.yml --extra-vars '{\"squid_port\": 3128, \"ssl_bump_enabled\": false, \"basic_auth_enabled\": false}'
```

## Troubleshooting

- **Port sudah dipakai**: Gunakan port lain saat prompt, atau cek `ss -tlnp | grep :3128`
- **Firewall blocking**: Pastikan port proxy dibuka di firewall (`ufw allow 3128` atau `firewall-cmd --add-port=3128/tcp --permanent`)
- **Domain diblokir**: Edit `/etc/squid/allowed_domains.txt`, lalu jalankan `squid -k reconfigure`
- **Squid gagal start**: Cek config: `squid -k parse`, cek log: `tail -f /var/log/squid/cache.log`
- **SELinux blocking**: Cek `audit2why < /var/log/audit/audit.log` atau jalankan ulang dengan `squid_selinux_enabled: true`
- **Butuh diagnostic lengkap**: Jalankan `sudo bash support-bundle.sh` dan kirim `.tar.gz` ke NR Support

## Persyaratan

- Linux (Ubuntu, Debian, CentOS, RHEL, Rocky, Alma, Fedora, SLES, openSUSE)
- Root atau sudo access
- curl atau wget (untuk download)
- Internet access (untuk download Ansible dan Squid)

## Lisensi

MIT License - lihat [LICENSE](LICENSE)
