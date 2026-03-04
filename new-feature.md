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
  - Alasan drop: Proxy host biasanya dedicated node yang sudah punya akses internet. Agent APM jarang diinstall di host yang sama dengan proxy.
- [x] **M5: Automated CA Rotation untuk SSL Bump**
  - Handling otomatis saat root CA SSL bump mendekati masa expired agar tidak ada downtime. Implementasi via cron script `rotate-squid-ca.sh`.

---

## Fitur Baru (Brainstorm Batch 2)

*Fitur tambahan hasil brainstorming, diurutkan berdasarkan impact-to-effort ratio.*

### Prioritas Tinggi

- [x] **N1: Region-Aware Configuration (US/EU)**
  - Saat ini semua 32+ endpoint (US + EU) di-whitelist dan di-tes. Di environment strict, customer hanya mau whitelist region mereka saja.
  - Solusi: Tambah prompt "Which NR region? [1] US  [2] EU  [3] Both (default)" di `install.sh`. Endpoint whitelist dan verification otomatis difilter per region.
  - Effort: Low | Value: High
- [x] **N2: Firewall Auto-Open**
  - Masalah paling sering setelah install: traffic tetap gagal karena port belum dibuka di firewall lokal.
  - Solusi: Deteksi `ufw`/`firewalld`/`iptables` dan tawarkan membuka port proxy di akhir instalasi.
  - Effort: Low | Value: High
- [x] **N3: Proxy Config Snippet Generator**
  - Summary akhir install hanya tampilkan `export https_proxy=...`. SE harus cari sendiri cara set proxy di tiap agent NR.
  - Solusi: Generate dan tampilkan ready-to-copy config snippets untuk NR Infra Agent (`newrelic-infra.yml`), Java APM (`-D` JVM args), Python APM (`newrelic.ini`), Node.js (`env`), .NET (`newrelic.config`).
  - Effort: Low | Value: High
- [x] **N4: Squid Metrics Monitoring via NR Flex Integration**
  - Standard Infra agent tidak pull custom metrics dari Squid secara native kecuali via Prometheus/JMX, tapi Squid punya cache manager default.
  - Solusi: Deploy custom `nri-flex` config (`squid-metrics-flex.yml`) jika `nr_integration_enabled=true` yang menjalankan HTTP GET polling ke `/squid-internal-mgr/counters` dan memecahnya menjadi Metrics di New Relic.
  - Effort: Medium | Value: High
  - Metrics yang di-expose:
    - `squid.requests_per_second` - Request rate
    - `squid.cache_hit_ratio` - Percentage of requests served from cache
    - `squid.active_connections` - Current client connections
    - `squid.memory_usage_mb` - Squid process memory
    - `squid.dns_median_svc_time` - DNS lookup latency
    - `squid.http_errors_count` - Error response count
  - Effort: Medium | Value: High

### Prioritas Menengah

- [ ] **N5: Config Backup Before Changes**
  - Setiap Ansible run otomatis backup `/etc/squid/` ke `/etc/squid/backup.YYYYMMDD_HHMMSS/`. Jika ada kesalahan, admin bisa rollback manual.
  - Effort: Low | Value: Medium
- [ ] **N6: Install Audit Log**
  - Pipe seluruh output `install.sh` ke `/var/log/nr-squid-install.log`. Untuk compliance audit di enterprise yang butuh bukti apa yang dijalankan.
  - Effort: Low | Value: Medium
- [ ] **N7: Access Log Quick Parser (`squid-report.sh`)**
  - CLI helper yang menampilkan: Top 10 blocked domains, Error count by HTTP code, Slowest requests. Berbasis `awk` saja, tanpa dependency tambahan.
  - Effort: Low | Value: Medium
- [ ] **N8: Scheduled Verify Cron**
  - Cron job opsional yang menjalankan `verify.yml` setiap malam dan menulis hasilnya ke log. Mendeteksi jika NR mengubah endpoint tanpa pemberitahuan.
  - Effort: Medium | Value: Medium

### Prioritas Rendah

- [ ] **N9: Health Check Endpoint**
  - Endpoint HTTP `/healthz` via Squid `cachemgr.cgi` yang mengembalikan 200 jika Squid healthy. Berguna untuk Load Balancer dan NR Synthetics monitoring.
  - Effort: Medium | Value: Low (niche)
- [ ] **N10: Proxy Performance Baseline**
  - Setelah install, ukur dan catat latency round-trip melalui proxy sebagai baseline. Referensi jika ada keluhan "proxy lambat" di kemudian hari.
  - Effort: Medium | Value: Low

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
  - Risiko: Package Squid default bawaan distro sering di-compile **tanpa** flag `--enable-snmp`. Harus diverifikasi manual (`squid -v | grep snmp`) sebelum dideploy. Alternatif yang lebih aman: gunakan N4 (Flex Integration via `squidclient`).
