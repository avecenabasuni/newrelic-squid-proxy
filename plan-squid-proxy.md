# Plan: Otomasi Squid Proxy untuk New Relic via Shell + Ansible

> **Dokumen ini adalah referensi utama bagi agentic IDE (Google Antigravity) untuk membangun project secara otonom.**
> Setiap requirement memiliki definisi "done" yang eksplisit agar agent bisa self-verify tanpa konfirmasi balik.

---

## 1. Problem Statement

Saat melakukan POC (Proof of Concept) New Relic, customer sering kali membutuhkan **forward proxy** untuk mengakses endpoint New Relic dari server yang tidak memiliki akses internet langsung. Saat ini, proses instalasi dan konfigurasi Squid Proxy dilakukan secara manual menggunakan script shell murni — yang rentan terhadap:

- **Tidak idempoten** — menjalankan script dua kali bisa merusak konfigurasi
- **Hard-coded config** — toggle fitur (SSL Bump, Auth) harus manual edit file
- **Tidak terstruktur** — satu file shell monolitik menangani OS detection, package install, config templating, dan service management
- **Error handling lemah** — race condition pada background process (`$?` vs `wait`)

**Solusi**: Membangun ulang project menggunakan arsitektur **shell bootstrap (`install.sh`) + Ansible playbook**, di mana:
- Shell menangani bootstrap ringan (OS detection, Ansible install, interactive prompt)
- Ansible menangani konfigurasi kompleks secara idempoten (templating, package, service, validation)

---

## 2. Goals & Non-Goals

### Goals (MVP)
| # | Goal | Keterangan |
|---|------|------------|
| G1 | One-liner install | `curl -sSL <URL>/install.sh \| bash` harus cukup untuk install & configure semuanya |
| G2 | Multi-distro Linux | Support apt (Ubuntu/Debian), yum (CentOS/RHEL 7), dnf (RHEL 8+/Fedora/Rocky/Alma), zypper (SLES) |
| G3 | SSL Bump toggle | Enable/disable via prompt, menghasilkan config yang benar secara otomatis |
| G4 | Basic Auth toggle | Enable/disable via prompt, password di-hash otomatis via `htpasswd` |
| G5 | Repo access | Proxy TIDAK boleh memblokir akses ke package repository OS |
| G6 | Automated verification | Setelah instalasi, koneksi ke semua New Relic endpoints diverifikasi otomatis |
| G7 | Idempoten | Menjalankan ulang `install.sh` tidak merusak konfigurasi yang sudah benar |

### Non-Goals
| # | Non-Goal | Alasan |
|---|----------|--------|
| NG1 | Windows support | Di-scope out dari MVP — Squid di Windows terlalu niche |
| NG2 | Multi-host deploy | MVP selalu install ke localhost — remote deploy bisa ditambahkan nanti |
| NG3 | GUI / Web UI | Overkill untuk use case POC |
| NG4 | Container/Docker | Customer POC biasanya pakai VM bare-metal, bukan container |

---

## 3. Tech Stack & Alasan Pemilihan

| Layer | Teknologi | Versi Minimum | Alasan |
|-------|-----------|---------------|--------|
| **Bootstrap** | Bash (`install.sh`) | bash 4+ | Zero dependency — semua Linux punya bash. Ideal untuk detect OS, install Ansible, dan interactive prompts |
| **Config Management** | Ansible (`ansible-core`) | **>= 2.14** | Idempoten, deklaratif, Jinja2 templating, multi-distro package abstraction (`ansible.builtin.package`), validasi config built-in. Versi 2.14+ dipilih karena: masih dalam maintenance window, `ansible.builtin.*` namespace stabil, dan tersedia di package repo semua distro target |
| **Templating** | Jinja2 (via Ansible) | — | Conditional blocks untuk SSL Bump & Auth — satu template `squid.conf.j2` menghasilkan semua varian config |
| **Verification** | `ansible.builtin.uri` | — | HTTP request ke endpoint New Relic langsung dari playbook, hasilnya structured (bukan text grep) |
| **Auth Hashing** | `htpasswd` CLI (via `ansible.builtin.command`) | — | Lebih portable daripada `community.general.htpasswd` module — tidak butuh collection tambahan, hanya butuh `apache2-utils` / `httpd-tools` yang sudah diinstall sebagai dependensi |

> [!IMPORTANT]
> **Ansible Collection Policy**: Project ini HANYA menggunakan `ansible.builtin.*` modules — tidak ada dependency ke `community.general` atau collection lainnya. Ini memastikan `ansible-core` saja cukup, tanpa perlu `ansible-galaxy collection install`.

### Mengapa Shell + Ansible, bukan Shell saja?

```
┌─────────────────────────────────────────────────────────────────┐
│                     PEMBAGIAN TANGGUNG JAWAB                     │
├────────────────────────┬────────────────────────────────────────┤
│ install.sh (Shell)     │ Ansible Playbook                       │
├────────────────────────┼────────────────────────────────────────┤
│ ✔ Detect OS & pkg mgr │ ✔ Install Squid (idempoten)            │
│ ✔ Install Ansible      │ ✔ Template squid.conf.j2               │
│ ✔ Interactive prompts  │ ✔ Manage SSL cert directory            │
│ ✔ Generate variables   │ ✔ Create htpasswd file                 │
│ ✔ Trigger playbook     │ ✔ Service enable/restart               │
│                        │ ✔ Config validation (squid -k parse)   │
│                        │ ✔ Endpoint verification (uri module)   │
└────────────────────────┴────────────────────────────────────────┘
```

- **Shell** unggul untuk: bootstrap ringan tanpa dependensi, user prompts (`read -p`), satu file download
- **Ansible** unggul untuk: idempoten config management, Jinja2 templating dengan conditionals, multi-distro package abstraction, structured verification output

---

## 4. Bootstrap & UX Flow

### Entry Point
```bash
curl -sSL https://raw.githubusercontent.com/avecenabasuni/newrelic-squid-proxy/main/install.sh | bash
```

### 4.1 Strategi Download Repository (Critical Design Decision)

> [!IMPORTANT]
> **Problem**: `install.sh` dijalankan via `curl | bash` — artinya hanya file `install.sh` yang ada di-memory saat eksekusi. Semua file Ansible (playbook, roles, templates) belum ada di disk. Script harus download repository **lengkap** sebelum bisa menjalankan Ansible.

**Solusi**: `install.sh` memiliki variabel `REPO_URL` dan `REPO_BRANCH` yang di-hardcode di bagian atas script, tapi bisa di-override via environment variable.

```bash
# ─── Configurable Repository Source ───────────────────────────────
# Override via environment variable jika repo URL berubah atau fork:
#   REPO_URL=https://github.com/my-fork/newrelic-squid-proxy.git bash install.sh
REPO_URL="${REPO_URL:-https://github.com/avecenabasuni/newrelic-squid-proxy.git}"
REPO_BRANCH="${REPO_BRANCH:-main}"
INSTALL_DIR="/opt/newrelic-squid-proxy"
```

**Strategi download (3-tier fallback)**:

```
┌─────────────────────────────────────────────────────────────────┐
│                  REPO DOWNLOAD STRATEGY                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Priority 1: Cek apakah $INSTALL_DIR sudah ada & valid          │
│  ├─ YES + site.yml exists → Skip download, pakai yang ada       │
│  │   (mendukung skenario: manual clone dulu, baru run install)  │
│  └─ NO → lanjut ke Priority 2                                   │
│                                                                 │
│  Priority 2: git clone (jika git tersedia)                      │
│  ├─ git clone --depth 1 --branch $REPO_BRANCH $REPO_URL         │
│  │   $INSTALL_DIR                                               │
│  └─ GAGAL → lanjut ke Priority 3                                │
│                                                                 │
│  Priority 3: curl/wget download tarball dari GitHub              │
│  ├─ URL: ${REPO_URL%.git}/archive/refs/heads/${REPO_BRANCH}.tar.gz │
│  ├─ Extract ke /tmp, lalu mv ke $INSTALL_DIR                    │
│  └─ GAGAL → exit 1 "Cannot download repository"                 │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Mengapa tiga tier?**
- **Tier 1 (local check)**: Mendukung user yang manual `git clone` dulu — pola ini umum di environment yang membatasi `curl | bash`
- **Tier 2 (git clone)**: Paling reliable, shallow clone hemat bandwidth, history tidak diperlukan
- **Tier 3 (tarball)**: Fallback untuk server tanpa git — GitHub menyediakan tarball otomatis di URL predictable

**Acceptance Criteria untuk download mechanism**:
- [ ] Variabel `REPO_URL` dan `REPO_BRANCH` bisa di-override via env var
- [ ] Jika `$INSTALL_DIR/site.yml` sudah ada, skip download dan tampilkan pesan "Using existing installation"
- [ ] Jika git tersedia, gunakan shallow clone ke `$INSTALL_DIR`
- [ ] Jika git tidak tersedia, download tarball via curl (atau wget jika curl tidak ada)
- [ ] Jika semua download method gagal, exit 1 dengan pesan error yang jelas
- [ ] Setelah download, validasi bahwa `$INSTALL_DIR/site.yml` ada

**Definisi Done**: Setelah step 5 selesai, `ls $INSTALL_DIR/site.yml` return exit code `0`.

### 4.2 Flow Diagram

```
┌──────────────────────────────────────────────────────────────────┐
│                         install.sh                                │
├──────────────────────────────────────────────────────────────────┤
│                                                                   │
│  1. Banner + metadata                                             │
│  2. Check: running as root / sudo?                                │
│     └─ NO → exit 1 with error message                             │
│  3. Detect OS & package manager                                   │
│     ├─ /etc/os-release → ID, VERSION_ID                           │
│     ├─ Map: ubuntu/debian → apt                                   │
│     │       centos/rhel 7 → yum                                   │
│     │       rocky/alma/rhel 8+/fedora → dnf                       │
│     │       sles/opensuse → zypper                                │
│     └─ UNKNOWN → exit 1                                           │
│  4. Install Ansible jika belum ada                                │
│     ├─ command -v ansible-playbook                                │
│     ├─ Cek versi: ansible --version >= 2.14                       │
│     ├─ apt: apt install -y ansible                                │
│     ├─ yum: yum install -y epel-release && yum install ansible    │
│     ├─ dnf: dnf install -y ansible-core                           │
│     ├─ zypper: zypper install -y ansible                          │
│     └─ Fallback: pip3 install ansible-core                        │
│  5. Download/clone repository ke $INSTALL_DIR                     │
│     ├─ Cek: $INSTALL_DIR/site.yml sudah ada? → skip               │
│     ├─ Jika git tersedia: git clone --depth 1 (shallow)           │
│     ├─ Fallback: curl download tarball + extract                  │
│     └─ Validasi: $INSTALL_DIR/site.yml harus ada                  │
│  6. Interactive prompts                                           │
│     ├─ Proxy port? [default: 3128]                                │
│     ├─ Enable SSL Bump? (y/n) [default: n]                       │
│     │   └─ YES: path CA cert? path CA key?                        │
│     ├─ Enable Basic Auth? (y/n) [default: n]                     │
│     │   └─ YES: username? password? (read -s)                     │
│     └─ Confirm summary → proceed?                                 │
│  7. Generate extra-vars JSON → /tmp/nr-squid-vars.json            │
│  8. cd $INSTALL_DIR && Run:                                       │
│     ansible-playbook site.yml --extra-vars @/tmp/nr-squid-vars.json│
│  9. Run: ansible-playbook verify.yml                               │
│          --extra-vars @/tmp/nr-squid-vars.json                     │
│ 10. Cleanup: rm -f /tmp/nr-squid-vars.json                        │
│ 11. Print summary & proxy usage instructions                      │
│                                                                   │
└──────────────────────────────────────────────────────────────────┘
```

### Prompt Summary (sebelum eksekusi)

Script harus menampilkan ringkasan konfigurasi sebelum menjalankan Ansible, contoh:

```
╔══════════════════════════════════════════════╗
║         New Relic Squid Proxy Setup          ║
╠══════════════════════════════════════════════╣
║  OS Detected  : Ubuntu 22.04                ║
║  Proxy Port   : 3128                        ║
║  SSL Bump     : disabled                    ║
║  Basic Auth   : enabled (user: admin)       ║
╠══════════════════════════════════════════════╣
║  Proceed with installation? (y/n)           ║
╚══════════════════════════════════════════════╝
```

---

## 5. Feature Scope MVP

### F1: OS Detection & Ansible Bootstrap

**Deskripsi**: `install.sh` mendeteksi distro Linux dan package manager, lalu menginstall Ansible (`ansible-core >= 2.14`) jika belum tersedia.

**Acceptance Criteria**:
- [ ] Script membaca `/etc/os-release` dan menentukan `PKG_MANAGER` (apt/yum/dnf/zypper)
- [ ] Jika `ansible-playbook` sudah ada di `$PATH` DAN versi >= 2.14, skip instalasi Ansible
- [ ] Jika Ansible belum ada atau versi terlalu lama, install menggunakan package manager yang terdeteksi
- [ ] Fallback: jika package manager gagal install Ansible, coba `pip3 install ansible-core`
- [ ] Jika OS tidak didukung, exit dengan kode `1` dan pesan error deskriptif

**Definisi Done**: Setelah `install.sh` selesai step 4, `ansible-playbook --version` return exit code `0` dan menampilkan versi >= 2.14.

---

### F2: Interactive Prompts & Variable Generation

**Deskripsi**: Script mengumpulkan konfigurasi dari user melalui prompt interaktif, lalu menghasilkan file JSON yang akan dipakai Ansible sebagai extra-vars.

**Acceptance Criteria**:
- [ ] Prompt proxy port, default `3128` jika user tekan Enter langsung
- [ ] Prompt SSL Bump (y/n), default `n`
  - [ ] Jika `y`: prompt path CA cert dan CA key, validasi file exists
- [ ] Prompt Basic Auth (y/n), default `n`
  - [ ] Jika `y`: prompt username dan password (password tidak ditampilkan saat diketik via `read -s`)
- [ ] Menampilkan summary konfirmasi sebelum eksekusi
- [ ] Generate `/tmp/nr-squid-vars.json` dengan format:

```json
{
  "squid_port": 3128,
  "ssl_bump_enabled": false,
  "ssl_bump_cert_path": "",
  "ssl_bump_key_path": "",
  "basic_auth_enabled": false,
  "basic_auth_username": "",
  "basic_auth_password": ""
}
```

**Definisi Done**: File `/tmp/nr-squid-vars.json` berisi JSON valid sesuai input user; `python3 -m json.tool /tmp/nr-squid-vars.json` return exit code `0`.

---

### F3: Ansible Role — Squid Installation (Multi-Distro)

**Deskripsi**: Role `squid_proxy` menginstall Squid dan dependensinya secara idempoten menggunakan `ansible.builtin.package`.

**Acceptance Criteria**:
- [ ] Squid terinstall di semua distro target via `ansible.builtin.package`
- [ ] Paket auth tools terinstall: `apache2-utils` (Debian/Ubuntu) atau `httpd-tools` (RHEL family)
- [ ] Task idempoten: menjalankan playbook dua kali, hasilnya `changed=0` pada run kedua

**Definisi Done**: `squid -v` return exit code `0` dan menampilkan versi Squid. Playbook run kedua seluruh tasks berstatus `ok`, bukan `changed`.

---

### F4: Jinja2 Template — `squid.conf.j2`

**Deskripsi**: Satu template Jinja2 yang menghasilkan konfigurasi Squid lengkap berdasarkan variabel. Menggantikan dua file statis (`squid.conf` dan `squid-ssl-bump.conf`).

**Acceptance Criteria**:
- [ ] Template menghasilkan blok network/port dengan RFC1918 subnets
- [ ] Domain whitelist mencakup semua endpoint New Relic (US + EU) + domain repo OS
- [ ] Blok SSL Bump hanya muncul jika `ssl_bump_enabled: true`
  - [ ] Port `3129` listening dengan path cert/key dari variabel
  - [ ] SSL Bump steps (peek → bump New Relic → splice all)
  - [ ] TLS outgoing minimum TLS 1.2
- [ ] Blok Basic Auth hanya muncul jika `basic_auth_enabled: true`
  - [ ] `auth_param` dan `acl authenticated_users` di-render
  - [ ] Access policy berubah: `http_access allow authenticated_users localnet allowed_domains`
- [ ] Blok logging, caching, privacy, dan coredump selalu ada
- [ ] Port proxy menggunakan variabel `{{ squid_port }}`

**Definisi Done**: `squid -k parse -f /etc/squid/squid.conf` return exit code `0` (config valid) untuk semua kombinasi toggle:
1. SSL Bump OFF, Auth OFF
2. SSL Bump ON, Auth OFF
3. SSL Bump OFF, Auth ON
4. SSL Bump ON, Auth ON

---

### F5: SSL Bump Setup

**Deskripsi**: Jika SSL Bump diaktifkan, Ansible menyiapkan direktori sertifikat dan SSL DB.

**Acceptance Criteria**:
- [ ] Direktori `/etc/squid/ssl_cert/` dibuat dengan permission `700`, owner `proxy` (atau user Squid sesuai distro)
- [ ] CA cert & key dicopy ke `/etc/squid/ssl_cert/` dari path yang diberikan user
- [ ] SSL DB diinisialisasi: `/var/lib/squid/ssl_db` via `security_file_certgen` (atau `/usr/lib/squid/security_file_certgen`)
  - [ ] Path `security_file_certgen` di-detect secara otomatis (berbeda antar distro)
- [ ] Task di-skip jika `ssl_bump_enabled: false`

**Definisi Done**: File CA cert dan key ada di `/etc/squid/ssl_cert/`, permission benar, dan `ls -la /var/lib/squid/ssl_db/` menunjukkan DB yang valid. Jika SSL Bump OFF, task berstatus `skipped`.

---

### F6: Basic Auth Setup

**Deskripsi**: Jika Basic Auth diaktifkan, Ansible membuat file htpasswd dan mengonfigurasi Squid.

> [!NOTE]
> **Keputusan**: Menggunakan `ansible.builtin.command` + `htpasswd` CLI, **bukan** `community.general.htpasswd` module. Alasan: lebih portable, tidak butuh `ansible-galaxy collection install community.general`, dan `htpasswd` CLI sudah tersedia dari `apache2-utils`/`httpd-tools` yang kita install sebagai dependensi Squid.

**Acceptance Criteria**:
- [ ] File `/etc/squid/passwords` dibuat dengan permission `640`, owner `{{ squid_user }}:{{ squid_group }}`
- [ ] Password di-hash menggunakan `ansible.builtin.command: htpasswd -cb {{ basic_auth_password_file }} {{ basic_auth_username }} {{ basic_auth_password }}`
- [ ] Task bersifat idempoten: cek apakah user sudah ada sebelum menjalankan `htpasswd` (menggunakan `creates` atau `grep` check)
- [ ] Akses tanpa credential return HTTP `407 Proxy Authentication Required`
- [ ] Akses dengan credential valid berfungsi normal
- [ ] Task di-skip jika `basic_auth_enabled: false`

**Definisi Done**:
- `curl -x http://localhost:{{ squid_port }} https://newrelic.com` return `407`
- `curl -x http://user:pass@localhost:{{ squid_port }} https://newrelic.com` return `200/301`
- Jika Auth OFF: `curl -x http://localhost:{{ squid_port }} https://newrelic.com` return `200/301` tanpa credential

---

### F7: Service Management

**Deskripsi**: Ansible mengelola service Squid — config validation, restart, enable at boot.

**Acceptance Criteria**:
- [ ] Config divalidasi sebelum restart via handler: `squid -k parse`
- [ ] Squid di-restart hanya jika config berubah (handler triggered by template task notify)
- [ ] Squid di-enable untuk start at boot: `systemctl enable squid`
- [ ] Status Squid dicek: `systemctl is-active squid` return `active`

**Definisi Done**: `systemctl is-active squid` return `active` dan `systemctl is-enabled squid` return `enabled`.

---

### F8: Endpoint Verification (Automated)

**Deskripsi**: Playbook `verify.yml` menguji koneksi ke semua endpoint New Relic melalui proxy yang baru di-setup.

**Acceptance Criteria**:
- [ ] Menguji minimal 32 endpoint (US + EU) dari `newrelic_endpoints` variable list
- [ ] Menggunakan `ansible.builtin.uri` dengan `use_proxy: false` dan `CONNECT` method simulasi melalui environment proxy
  - Alternatif: `ansible.builtin.command` + `curl -x http://localhost:{{ squid_port }}`
- [ ] HTTP status `200`, `301`, `400`, atau `404` dianggap sukses
- [ ] Hasilnya ditampilkan sebagai summary: jumlah sukses vs gagal
- [ ] Jika basic auth aktif, request disertakan credential

**Definisi Done**: Output playbook menampilkan summary dengan format:
```
TASK [verify : Display results] ****
ok: [localhost] => {
    "msg": "Verification complete: 32/32 endpoints reachable"
}
```
Jika ada yang gagal, ditampilkan daftar endpoint yang gagal beserta HTTP status code-nya.

---

## 6. Struktur File Project

```
newrelic-squid-proxy/
├── install.sh                          # Bootstrap: detect OS, install Ansible, prompts, run playbook
├── ansible.cfg                         # Ansible config (local, no SSH)
├── inventory/
│   └── localhost.ini                   # Inventory statis → localhost connection=local
├── site.yml                            # Main playbook: install & configure Squid
├── verify.yml                          # Verification playbook: test endpoints
├── group_vars/
│   └── all.yml                         # Default variables (overridden by extra-vars)
├── roles/
│   ├── squid_proxy/
│   │   ├── defaults/
│   │   │   └── main.yml                # Default role variables
│   │   ├── vars/
│   │   │   ├── main.yml                # Shared vars (endpoint list, domain list)
│   │   │   ├── Debian.yml              # Debian/Ubuntu-specific vars (package names, paths)
│   │   │   ├── RedHat.yml              # RHEL/CentOS/Rocky/Alma-specific vars
│   │   │   └── Suse.yml                # SLES/openSUSE-specific vars
│   │   ├── tasks/
│   │   │   ├── main.yml                # Task router: include OS-specific + common
│   │   │   ├── install.yml             # Install Squid & dependencies
│   │   │   ├── configure.yml           # Template config, setup dirs
│   │   │   ├── ssl_bump.yml            # SSL Bump setup (conditional)
│   │   │   ├── auth.yml                # Basic Auth setup (conditional)
│   │   │   └── service.yml             # Enable, validate, restart Squid
│   │   ├── handlers/
│   │   │   └── main.yml                # Handler: validate config → restart squid
│   │   └── templates/
│   │       └── squid.conf.j2           # Jinja2 template — single source of truth
│   └── verify/
│       ├── defaults/
│       │   └── main.yml                # Verify role defaults
│       ├── vars/
│       │   └── main.yml                # Endpoint list for verification
│       └── tasks/
│           └── main.yml                # URI checks + summary output
├── legacy/                             # File lama, dipertahankan sebagai referensi
│   ├── squid.conf                      # Konfigurasi statis versi lama
│   ├── squid-ssl-bump.conf             # Konfigurasi SSL Bump versi lama
│   ├── newrelic-squid-proxy.sh          # Script instalasi versi lama
│   └── newrelic-endpoint-test.sh        # Script test endpoint versi lama
├── .gitignore
├── LICENSE
├── plan-squid-proxy.md                 # Dokumen planning ini
└── README.md                           # Updated documentation
```

---

## 7. Variabel Utama & Default Values

### `roles/squid_proxy/defaults/main.yml`

```yaml
# ─── Network ──────────────────────────────────
squid_port: 3128
squid_localnet:
  - "10.0.0.0/8"
  - "172.16.0.0/12"
  - "192.168.0.0/16"

# ─── SSL Bump ─────────────────────────────────
ssl_bump_enabled: false
ssl_bump_port: 3129
ssl_bump_cert_path: ""          # Path CA cert di host sumber (sebelum copy)
ssl_bump_key_path: ""           # Path CA key di host sumber (sebelum copy)
ssl_bump_cert_dest: "/etc/squid/ssl_cert/myCA.crt"
ssl_bump_key_dest: "/etc/squid/ssl_cert/myCA.key"
ssl_bump_db_path: "/var/lib/squid/ssl_db"
squid_tls_min_version: "1.2"

# ─── Basic Auth ────────────────────────────────
basic_auth_enabled: false
basic_auth_username: ""
basic_auth_password: ""
basic_auth_password_file: "/etc/squid/passwords"
basic_auth_realm: "Squid Proxy Authentication"

# ─── Logging ───────────────────────────────────
squid_access_log: "/var/log/squid/access.log"
squid_cache_log: "/var/log/squid/cache.log"
squid_logfile_rotate: 10

# ─── Cache ─────────────────────────────────────
squid_cache_mem: "256 MB"
squid_max_object_size_in_memory: "512 KB"

# ─── Privacy ───────────────────────────────────
squid_forwarded_for: "off"
```

### `roles/squid_proxy/vars/main.yml` (non-overridable)

```yaml
# ─── New Relic Allowed Domains ─────────────────
newrelic_domains:
  - ".newrelic.com"
  - ".eu.newrelic.com"
  - ".nr-data.net"
  - "download.newrelic.com"
  - "api.newrelic.com"
  - "infra-api.newrelic.com"
  - "identity-api.newrelic.com"
  - "infrastructure-command-api.newrelic.com"
  - "nr-downloads-main.s3.us-east-1.amazonaws.com"
  - ".js-agent.newrelic.com"
  - ".synthetics-horde.nr-data.net"
  - ".synthetics-horde.eu01.nr-data.net"

# ─── OS Repo Domains (agar installer NR bisa pull packages) ──
os_repo_domains:
  - ".ubuntu.com"
  - ".debian.org"
  - ".security.debian.org"
  - ".rockylinux.org"
  - ".almalinux.org"
  - ".centos.org"
  - ".fedoraproject.org"
  - ".rpmfusion.org"
  - ".epel.mirror"
  - ".dl.fedoraproject.org"
  - ".amazonaws.com"
  - ".cloudfront.net"

# Merged list untuk template
allowed_domains: "{{ newrelic_domains + os_repo_domains }}"

# ─── New Relic Endpoints (untuk verification) ──
newrelic_endpoints:
  - "https://collector.newrelic.com"
  - "https://aws-api.newrelic.com"
  - "https://cloud-collector.newrelic.com"
  - "https://bam.nr-data.net"
  - "https://bam-cell.nr-data.net"
  - "https://csec.nr-data.net"
  - "https://insights-collector.newrelic.com"
  - "https://log-api.newrelic.com"
  - "https://metric-api.newrelic.com"
  - "https://trace-api.newrelic.com"
  - "https://infra-api.newrelic.com"
  - "https://identity-api.newrelic.com"
  - "https://infrastructure-command-api.newrelic.com"
  - "https://nrql-lookup.service.newrelic.com"
  - "https://mobile-collector.newrelic.com"
  - "https://mobile-crash.newrelic.com"
  - "https://mobile-symbol-upload.newrelic.com"
  - "https://otlp.nr-data.net"
  - "https://collector.eu.newrelic.com"
  - "https://collector.eu01.nr-data.net"
  - "https://aws-api.eu.newrelic.com"
  - "https://aws-api.eu01.nr-data.net"
  - "https://cloud-collector.eu.newrelic.com"
  - "https://bam.eu01.nr-data.net"
  - "https://csec.eu01.nr-data.net"
  - "https://insights-collector.eu01.nr-data.net"
  - "https://log-api.eu.newrelic.com"
  - "https://metric-api.eu.newrelic.com"
  - "https://trace-api.eu.newrelic.com"
  - "https://infra-api.eu.newrelic.com"
  - "https://infra-api.eu01.nr-data.net"
  - "https://identity-api.eu.newrelic.com"
  - "https://infrastructure-command-api.eu.newrelic.com"
  - "https://nrql-lookup.service.eu.newrelic.com"
  - "https://mobile-collector.eu01.nr-data.net"
  - "https://mobile-crash.eu01.nr-data.net"
  - "https://mobile-symbol-upload.eu01.nr-data.net"
  - "https://otlp.eu01.nr-data.net"
  - "https://download.newrelic.com"
```

### `roles/squid_proxy/vars/Debian.yml`

```yaml
squid_package_name: "squid"
squid_auth_package: "apache2-utils"
squid_service_name: "squid"
squid_user: "proxy"
squid_group: "proxy"
squid_ncsa_auth_path: "/usr/lib/squid/basic_ncsa_auth"
squid_certgen_path: "/usr/lib/squid/security_file_certgen"
```

### `roles/squid_proxy/vars/RedHat.yml`

```yaml
squid_package_name: "squid"
squid_auth_package: "httpd-tools"
squid_service_name: "squid"
squid_user: "squid"
squid_group: "squid"
squid_ncsa_auth_path: "/usr/lib64/squid/basic_ncsa_auth"
squid_certgen_path: "/usr/lib64/squid/security_file_certgen"
```

### `roles/squid_proxy/vars/Suse.yml`

```yaml
squid_package_name: "squid"
squid_auth_package: "apache2-utils"
squid_service_name: "squid"
squid_user: "squid"
squid_group: "squid"
squid_ncsa_auth_path: "/usr/sbin/basic_ncsa_auth"
squid_certgen_path: "/usr/sbin/security_file_certgen"
```

---

## 8. Key Ansible Tasks (Pseudo-code)

### `tasks/main.yml` — Router

```yaml
- name: Include OS-specific variables
  ansible.builtin.include_vars: "{{ ansible_os_family }}.yml"

- name: Install Squid
  ansible.builtin.import_tasks: install.yml

- name: Configure Squid
  ansible.builtin.import_tasks: configure.yml

- name: Setup SSL Bump
  ansible.builtin.import_tasks: ssl_bump.yml
  when: ssl_bump_enabled | bool

- name: Setup Basic Auth
  ansible.builtin.import_tasks: auth.yml
  when: basic_auth_enabled | bool

- name: Manage Squid service
  ansible.builtin.import_tasks: service.yml
```

### Handler — Validate & Restart

```yaml
- name: Validate squid config
  ansible.builtin.command: squid -k parse
  changed_when: false
  listen: "restart squid"

- name: Restart squid
  ansible.builtin.service:
    name: "{{ squid_service_name }}"
    state: restarted
  listen: "restart squid"
```

### Verify — Endpoint Check (conceptual)

```yaml
- name: Test New Relic endpoints via proxy
  ansible.builtin.uri:
    url: "{{ item }}"
    method: GET
    status_code: [200, 301, 400, 404]
    validate_certs: false
    timeout: 10
  environment:
    http_proxy: "http://{{ basic_auth_credentials }}localhost:{{ squid_port }}"
    https_proxy: "http://{{ basic_auth_credentials }}localhost:{{ squid_port }}"
  loop: "{{ newrelic_endpoints }}"
  register: endpoint_results
  ignore_errors: true

- name: Display verification summary
  ansible.builtin.debug:
    msg: >
      Verification complete: {{ endpoint_results.results | selectattr('status', 'defined')
      | selectattr('failed', 'equalto', false) | list | length }}/{{ newrelic_endpoints | length }}
      endpoints reachable
```

---

## 9. Risiko Teknis & Mitigasi

| # | Risiko | Dampak | Mitigasi |
|---|--------|--------|----------|
| R1 | Ansible belum tersedia di repo OS tertentu (SLES lama, minimal install) | Bootstrap gagal | Tambahkan fallback: install via `pip3 install ansible` jika package manager gagal |
| R2 | Path `security_file_certgen` berbeda antar distro dan versi Squid | SSL Bump setup gagal | Gunakan `find / -name security_file_certgen` di task dengan `register`, atau hardcode per OS family di vars |
| R3 | Package `squid` belum ada di repo (EPEL belum di-enable di RHEL) | Instalasi gagal | Task pertama: enable EPEL repo di RHEL family sebelum install Squid |
| R4 | Port 3128/3129 sudah dipakai service lain | Squid gagal start | Tambahkan pre-check: `ss -tlnp | grep :{{ squid_port }}` — warn user jika port occupied |
| R5 | CA cert/key yang diberikan user invalid / format salah | SSL Bump tidak berfungsi | Validasi cert dengan `openssl x509 -in <cert> -noout` sebelum copy |
| R6 | Firewall blocking port proxy | Proxy tidak bisa diakses dari client lain | Dokumentasikan di README, tapi jangan auto-modify firewall (terlalu invasif) |
| R7 | `curl \| bash` diblokir oleh policy perusahaan | User tidak bisa install | Sediakan instruksi alternatif: manual download + `bash install.sh` |

---

## 10. Open Questions

| # | Pertanyaan | Status | Keputusan |
|---|-----------|--------|----------|
| Q1 | Apakah perlu support Ansible versi minimum tertentu? | **RESOLVED** | `ansible-core >= 2.14` — versi ini masih dalam maintenance window, `ansible.builtin.*` namespace stabil, tersedia di package repo semua distro target. Berdasarkan riset Ansible docs: versi 2.14 adalah batas bawah yang aman untuk fitur yang kita gunakan |
| Q2 | Apakah `community.general` collection (untuk `htpasswd` module) bisa diasumsikan tersedia? | **RESOLVED** | **TIDAK** — gunakan `ansible.builtin.command` + `htpasswd` CLI. Lebih portable, zero extra dependency, `htpasswd` sudah tersedia dari `apache2-utils`/`httpd-tools` yang diinstall sebagai dependensi Squid |
| Q3 | Apakah repo lama harus dihapus atau dipertahankan? | **RESOLVED** | Pindahkan ke folder `legacy/` — repo tetap bersih, file lama tersimpan sebagai referensi |
| Q4 | Apakah proxy harus bisa diakses oleh host lain selain localhost? | **RESOLVED** | **YA** — proxy listen di `0.0.0.0:{{ squid_port }}` agar bisa diakses dari host lain. ACL membatasi akses ke `localnet` (RFC1918: `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`) |
| Q5 | Download repo via git clone atau tarball? | **RESOLVED** | 3-tier fallback: (1) cek lokal dulu, (2) `git clone --depth 1`, (3) tarball via curl. Lihat Section 4.1 untuk detail |
| Q6 | URL repo hardcoded atau configurable? | **RESOLVED** | Configurable via environment variable `REPO_URL` dan `REPO_BRANCH`, dengan default ke GitHub repo utama. Lihat Section 4.1 |

---

## 11. Verification Plan

### 11.1 Automated Tests (via `verify.yml`)

| Test | Cara Eksekusi | Expected Result |
|------|--------------|-----------------|
| Squid service running | `ansible.builtin.service_facts` → assert `squid.service` state `running` | `running` |
| Squid config valid | `squid -k parse` → exit code 0 | `rc == 0` |
| Port listening | `ansible.builtin.wait_for: port={{ squid_port }}` | port reachable |
| NR endpoints reachable (no auth) | `ansible.builtin.uri` via proxy → status `[200,301,400,404]` | 32/32 pass |
| NR endpoints reachable (with auth) | `ansible.builtin.uri` via proxy dengan credential → status `[200,301,400,404]` | 32/32 pass |
| Auth 407 (when enabled) | `curl -x http://localhost:{{ squid_port }} https://newrelic.com` tanpa credential | HTTP 407 |
| SSL Bump port listening (when enabled) | `ansible.builtin.wait_for: port={{ ssl_bump_port }}` | port reachable |
| Idempotency test | Run `site.yml` dua kali, cek output run kedua | `changed=0` |

**Cara menjalankan**:
```bash
# Full verification
ansible-playbook -i inventory/localhost.ini verify.yml --extra-vars @/tmp/nr-squid-vars.json

# Idempotency check
ansible-playbook -i inventory/localhost.ini site.yml --extra-vars @/tmp/nr-squid-vars.json | tail -1
# Expected: changed=0
```

### 11.2 Manual Verification

> **Catatan**: Manual verification dilakukan oleh user di server target setelah deployment.

| # | Langkah | Expected |
|---|---------|----------|
| 1 | `systemctl status squid` | Active (running) |
| 2 | `curl -x http://localhost:3128 https://newrelic.com -v` | HTTP 200/301 |
| 3 | `curl -x http://localhost:3128 https://google.com -v` | HTTP 403 (domain not in whitelist) |
| 4 | (Auth ON) `curl -x http://localhost:3128 https://newrelic.com` | HTTP 407 |
| 5 | (Auth ON) `curl -x http://user:pass@localhost:3128 https://newrelic.com` | HTTP 200/301 |
| 6 | (SSL Bump ON) `curl -x http://localhost:3129 https://newrelic.com -v --proxy-cacert /etc/squid/ssl_cert/myCA.crt` | HTTP 200 with MITM cert |

---

## 12. Execution Order (untuk Agent)

Agent harus mengeksekusi dalam urutan ini:

1. **Buat struktur direktori** — semua folder sesuai Section 6, termasuk `legacy/`
2. **Pindahkan file lama ke `legacy/`** — `squid.conf`, `squid-ssl-bump.conf`, `newrelic-squid-proxy.sh`, `newrelic-endpoint-test.sh`
3. **Tulis `ansible.cfg`** — `[defaults] inventory = inventory/localhost.ini`, `host_key_checking = False`
4. **Tulis `inventory/localhost.ini`** — `localhost ansible_connection=local`
5. **Tulis `group_vars/all.yml`** — kosong (semua defaults di role)
6. **Tulis `roles/squid_proxy/defaults/main.yml`** — sesuai Section 7
7. **Tulis `roles/squid_proxy/vars/*.yml`** — `main.yml`, `Debian.yml`, `RedHat.yml`, `Suse.yml`
8. **Tulis `roles/squid_proxy/templates/squid.conf.j2`** — berdasarkan existing `legacy/squid.conf` + `legacy/squid-ssl-bump.conf` dengan Jinja2 conditionals
9. **Tulis `roles/squid_proxy/tasks/*.yml`** — `main.yml`, `install.yml`, `configure.yml`, `ssl_bump.yml`, `auth.yml`, `service.yml`
10. **Tulis `roles/squid_proxy/handlers/main.yml`** — validate + restart handler
11. **Tulis `roles/verify/`** — tasks dan vars
12. **Tulis `site.yml`** — include role `squid_proxy`
13. **Tulis `verify.yml`** — include role `verify`
14. **Tulis `install.sh`** — bootstrap script sesuai Section 4 (dengan `REPO_URL`/`REPO_BRANCH` configurable dan 3-tier download fallback)
15. **Update `README.md`** — dokumentasi baru
16. **Update `.gitignore`** — tambahkan `/tmp/nr-squid-vars.json`, `*.retry`, `legacy/` (opsional)
17. **Verifikasi** — syntax check semua YAML: `ansible-playbook --syntax-check site.yml verify.yml`
