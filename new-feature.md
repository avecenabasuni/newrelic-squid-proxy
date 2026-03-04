# Future Enhancements & New Features Roadmap

> **Terakhir diverifikasi**: 4 Maret 2026
> **Sumber referensi**: New Relic Network Docs & EOL Announcements

Berikut adalah roadmap fitur untuk membuat `newrelic-squid-proxy` menjadi lebih robust dan enterprise-ready, diurutkan berdasarkan prioritas dan relevansi untuk eksekusi POC New Relic.

---

## 🔴 Prioritas Tinggi (High Priority)
*Langsung relevan untuk mengatasi blocker operasional di banyak enterprise environment selama POC.*

1.  **SELinux / AppArmor Handling**
    *   **Konteks**: Blocker utama di distro RHEL-based. Tanpa SELinux context yang benar (`squid_port_t`, `squid_cache_t`), Squid bisa gagal start atau gagal binding port di mode enforcing tanpa pesan error yang jelas bagi non-admin.
    *   **Action**: Menambahkan task Ansible khusus untuk setup SELinux context & booleans.
2.  **Corporate Proxy Chaining (Cache Peer)**
    *   **Konteks**: Sangat umum di enterprise di mana server lokal tidak punya direct internet access sama sekali. Proxy kita perlu me-route outbound traffic lewat proxy korporat utama.
    *   **Action**: Menambahkan input variabel untuk upstream proxy (`cache_peer`).
3.  **Uninstall Script (`uninstall.sh` / `teardown.yml`)**
    *   **Konteks**: Dibutuhkan untuk evaluasi POC yang bersih. Engineer harus bisa menghapus semua modifikasi (package, config, routing) dengan satu command.
4.  **Dry-run Mode (`--dry-run`)**
    *   **Konteks**: Standard practice untuk installer shell script. Meningkatkan kepercayaan tim sekuritas customer sebelum mengeksekusi otomatisasi.

---

## 🟡 Prioritas Menengah (Medium Priority)
*Sangat direkomendasikan untuk stabilitas dan troubleshooting operasional pasca-POC awal.*

1.  **Dynamic / External ACLs**
    *   **Konteks**: Memisahkan list allowed domains NR ke file external (`/etc/squid/allowed_domains.txt`) yang bisa di-reload Squid tanpa re-run seluruh Ansible playbook. Memudahkan jika NR menambah endpoint baru.
2.  **Log Forwarding (Fluent Bit / NR Agent)**
    *   **Konteks**: Mengkonfigurasi log forwarder agar `access.log` dan `cache.log` Squid langsung terpantau di New Relic Logs untuk analisis error terpusat.
3.  **One-Click Diagnostic Archive (`support-bundle.sh`)**
    *   **Konteks**: Script untuk membungkus otomatis konfigurasi, logs, test result, dan mem limit ke `.tar.gz`. Mengurangi bolak-balik eskalasi saat ada issue jaringan yang harus diinvestigasi NR Support.
4.  **Agent Auto-Configuration Tool**
    *   **Konteks**: Helper script untuk otomatis meng-scan environment lokal dan menyuntikkan setting proxy ke NR agents (Infra, APM) jika ada di server yang sama.
5.  **Automated CA Rotation untuk SSL Bump**
    *   **Konteks**: Handling otomatis saat root CA SSL bump (yang generate-on-the-fly) mendekati masa expired agar tidak ada downtime.

---

## 🟢 Prioritas Rendah (Low Priority / Niche)
*Fitur advanced untuk long-term deployment atau use-case spesifik, tidak blocking untuk POC.*

1.  **Containerized Support (Docker/Podman)**
    *   **Konteks**: Menyediakan versi container. (Catatan: Bertentangan dengan tujuan non-goal MVP awal yang berfokus ke host-level instansiasi untuk kemudahan agent lokal).
2.  **High Availability (Keepalived / HAProxy)**
    *   **Konteks**: Setup active-active load balancing. Overkill untuk POC, dibutuhkan hanya jika proxy dipakai secara production cross-datacenter.
3.  **Bandwidth Throttling (Delay Pools)**
    *   **Konteks**: QOS untuk membatasi pemakaian bandwidth internet oleh agen NR. Jarang jadi requirement.
4.  **LDAP / Active Directory Integration**
    *   **Konteks**: Integrasi enterprise identity provider untuk otentikasi proxy. Butuh dependency eksternal besar.
5.  **Synthetics Job Manager (SJM) Profiles**
    *   **Konteks**: Preset konfigurasi tambahan untuk kebutuhan network khusus SJM. *(Catatan: Containerized Private Minion / CPM telah EOL per 22 Oktober 2024)*.
6.  **Dualstack Endpoints Support**
    *   **Konteks**: Future-proofing mendukung IPv6 (HTTP/3) allowed domains New Relic (seperti `collector.dualstack.nr-data.net`).
7.  **Companion Health Check API & Web GUI**
    *   **Konteks**: External local web UI / API service untuk memanage allowed domains tanpa CLI, serta endpoint testing untuk Load Balancer health-check.

---

## ⚪ Perlu Validasi Lingkungan
*Ide operasional yang berpotensi destructive atau sangat bergantung pada default OS target.*

1.  **Transparent Proxying (TPROXY)**
    *   **Risiko**: Mengubah iptables/nftables agar traffic HTTP/S otomatis lewat proxy bisa merusak (break) routing internal enterprise jika tidak hati-hati.
2.  **Squid SNMP Metrics Exporter**
    *   **Risiko**: Walaupun NR Infra agent memiliki SNMP native integration, package Squid default bawaan distro (seperti `apt` atau `yum`) sering di-compile **tanpa** flag `--enable-snmp`. Harus diverifikasi manual (`squid -v | grep snmp`) sebelum bisa dideploy. Jika tidak, butuh eksportir Prometheus terpisah.
