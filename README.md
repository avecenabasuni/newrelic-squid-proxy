# New Relic Squid Proxy

Otomasi instalasi dan konfigurasi **Squid Proxy** untuk mendukung POC New Relic di environment yang membutuhkan forward proxy.

## Fitur

- **One-liner install** — `curl -sSL <URL>/install.sh | bash`
- **Multi-distro** — Ubuntu, Debian, CentOS, RHEL, Rocky, Alma, Fedora, SLES, openSUSE
- **SSL Bump (opsional)** — MITM interception untuk TLS traffic ke New Relic
- **Basic Auth (opsional)** — Autentikasi proxy via htpasswd
- **Domain whitelist** — Hanya mengizinkan akses ke endpoint New Relic + OS package repos
- **Automated verification** — Uji koneksi ke 32+ endpoint New Relic (US + EU) otomatis
- **Idempoten** — Aman dijalankan berulang kali

## Quick Start

### Instalasi Otomatis (Recommended)

```bash
curl -sSL https://raw.githubusercontent.com/avecenabasuni/newrelic-squid-proxy/main/install.sh | bash
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

### Override Repository URL

```bash
REPO_URL=https://github.com/my-fork/newrelic-squid-proxy.git bash install.sh
```

## Konfigurasi

Semua konfigurasi ditanyakan via prompt interaktif saat instalasi:

| Parameter | Default | Deskripsi |
|-----------|---------|-----------|
| Proxy Port | `3128` | Port HTTP proxy |
| SSL Bump | `disabled` | Enable MITM interception (butuh CA cert & key) |
| Basic Auth | `disabled` | Enable autentikasi proxy (butuh username & password) |

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

## Struktur Project

```
├── install.sh                  # Bootstrap script
├── ansible.cfg                 # Ansible configuration
├── inventory/localhost.ini     # Localhost inventory
├── site.yml                    # Main installation playbook
├── verify.yml                  # Verification playbook
├── roles/
│   ├── squid_proxy/            # Squid installation & configuration role
│   │   ├── defaults/main.yml   # Default variables
│   │   ├── vars/               # OS-specific variables
│   │   ├── tasks/              # Installation & configuration tasks
│   │   ├── handlers/           # Service restart handlers
│   │   └── templates/          # squid.conf.j2 Jinja2 template
│   └── verify/                 # Endpoint verification role
├── legacy/                     # File konfigurasi versi lama (referensi)
└── plan-squid-proxy.md         # Dokumen perencanaan
```

## Jalankan Ulang Playbook Secara Manual

```bash
cd /opt/newrelic-squid-proxy

# Install/reconfigure
ansible-playbook site.yml --extra-vars '{"squid_port": 3128, "ssl_bump_enabled": false, "basic_auth_enabled": false}'

# Verify
ansible-playbook verify.yml --extra-vars '{"squid_port": 3128, "ssl_bump_enabled": false, "basic_auth_enabled": false}'
```

## Troubleshooting

- **Port sudah dipakai**: Gunakan port lain saat prompt, atau cek `ss -tlnp | grep :3128`
- **Firewall blocking**: Pastikan port proxy dibuka di firewall (`ufw allow 3128` atau `firewall-cmd --add-port=3128/tcp --permanent`)
- **Domain diblokir**: Edit whitelist di `roles/squid_proxy/vars/main.yml`, lalu jalankan ulang `ansible-playbook site.yml`
- **Squid gagal start**: Cek config: `squid -k parse`, cek log: `tail -f /var/log/squid/cache.log`

## Persyaratan

- Linux (Ubuntu, Debian, CentOS, RHEL, Rocky, Alma, Fedora, SLES, openSUSE)
- Root atau sudo access
- curl atau wget (untuk download)
- Internet access (untuk download Ansible dan Squid)

## Lisensi

MIT License — lihat [LICENSE](LICENSE)
