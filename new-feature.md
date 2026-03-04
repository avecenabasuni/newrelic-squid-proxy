# Future Enhancements & New Features Roadmap

> **Terakhir diperbarui**: 4 Maret 2026
> **Sumber referensi**: New Relic Network Docs & EOL Announcements

Roadmap fitur untuk membuat `newrelic-squid-proxy` menjadi lebih robust dan enterprise-ready, diurutkan berdasarkan prioritas dan relevansi untuk eksekusi POC New Relic.

---

## Prioritas Tinggi (High Priority) - SELESAI

*Langsung relevan untuk mengatasi blocker operasional di banyak enterprise environment selama POC.*

- [x] **P1: SELinux / AppArmor Handling**
    - Blocker utama di distro RHEL-based. Tanpa SELinux context yang benar (`squid_port_t`, `squid_cache_t`), Squid bisa gagal start.
    - Implementasi: `roles/squid_proxy/tasks/selinux.yml`
- [x] **P2: Corporate Proxy Chaining (Cache Peer)**
    - Untuk enterprise di mana server lokal tidak punya direct internet access. Proxy ini me-route outbound traffic lewat proxy korporat utama.
    - Implementasi: Prompt interaktif di `install.sh`, template `cache_peer` di `squid.conf.j2`
- [x] **P3: Uninstall Script**
    - Evaluasi POC yang bersih. Engineer bisa menghapus semua modifikasi dengan satu command.
    - Implementasi: `uninstall.sh` (standalone) + `teardown.yml` (Ansible playbook)
- [x] **P4: Dry-run Mode**
    - Standard practice untuk installer shell script. Meningkatkan kepercayaan tim sekuritas customer.
    - Implementasi: `bash install.sh --dry-run` (Ansible `--check --diff`)

---

## Prioritas Menengah (Medium Priority) - SEBAGIAN SELESAI

*Sangat direkomendasikan untuk stabilitas dan troubleshooting operasional pasca-POC awal.*

- [x] **M1: Dynamic / External ACLs**
    - Memisahkan list allowed domains ke file external (`/etc/squid/allowed_domains.txt`) yang bisa di-reload Squid tanpa re-run Ansible.
    - Implementasi: `allowed_domains.txt.j2`, `dynamic_acl.yml`, handler `Reconfigure Squid`
- [x] **M2: Log Forwarding (NR Infra Agent)**
    - Forward `access.log` dan `cache.log` Squid ke New Relic Logs via NR Infrastructure Agent (embedded Fluent Bit).
    - Implementasi: `nr-logging.yml.j2`, `log_forwarding.yml`, variabel `log_forwarding_enabled`
- [x] **M3: One-Click Diagnostic Archive**
    - Script untuk membungkus otomatis konfigurasi, logs, test result ke `.tar.gz`. Mengurangi bolak-balik eskalasi saat ada issue jaringan.
    - Implementasi: `support-bundle.sh`
- [~] ~~**M4: Agent Auto-Configuration Tool**~~ *(Dropped)*
    - Helper script untuk meng-scan environment lokal dan menyuntikkan setting proxy ke NR agents.
    - Alasan drop: Proxy host biasanya dedicated node yang sudah punya akses internet. Agent APM jarang diinstall di host yang sama dengan proxy.
- [ ] **M5: Automated CA Rotation untuk SSL Bump**
    - Handling otomatis saat root CA SSL bump mendekati masa expired agar tidak ada downtime.

---

## Prioritas Rendah (Low Priority / Niche)

*Fitur advanced untuk long-term deployment atau use-case spesifik, tidak blocking untuk POC.*

- [ ] **Containerized Support (Docker/Podman)**
    - Menyediakan versi container. Bertentangan dengan tujuan MVP yang berfokus ke host-level.
- [ ] **High Availability (Keepalived / HAProxy)**
    - Setup active-active load balancing. Overkill untuk POC.
- [ ] **Bandwidth Throttling (Delay Pools)**
    - QOS untuk membatasi bandwidth internet oleh agen NR. Jarang jadi requirement.
- [ ] **LDAP / Active Directory Integration**
    - Integrasi enterprise identity provider untuk otentikasi proxy. Butuh dependency besar.
- [ ] **Synthetics Job Manager (SJM) Profiles**
    - Preset konfigurasi untuk kebutuhan network khusus SJM. *(CPM telah EOL per 22 Oktober 2024)*.
- [ ] **Dualstack Endpoints Support**
    - Future-proofing mendukung IPv6 (HTTP/3) allowed domains New Relic.
- [ ] **Companion Health Check API & Web GUI**
    - Web UI / API service untuk manage allowed domains tanpa CLI, serta endpoint testing untuk Load Balancer health-check.

---

## Perlu Validasi Lingkungan

*Ide operasional yang berpotensi destructive atau sangat bergantung pada default OS target.*

- [ ] **Transparent Proxying (TPROXY)**
    - Risiko: Mengubah iptables/nftables agar traffic HTTP/S otomatis lewat proxy bisa merusak routing internal enterprise.
- [ ] **Squid SNMP Metrics Exporter**
    - Risiko: Package Squid default bawaan distro sering di-compile **tanpa** flag `--enable-snmp`. Harus diverifikasi manual (`squid -v | grep snmp`) sebelum dideploy.
