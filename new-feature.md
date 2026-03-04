# Future Enhancements & New Features

Berikut adalah beberapa ide fitur tambahan yang bisa diimplementasikan ke depannya untuk membuat `newrelic-squid-proxy` menjadi lebih robust dan enterprise-ready:

## 1. Observabilitas (Monitoring & Logging)
*   **Squid Metrics Exporter**: Mengotomatisasi instalasi dan konfigurasi `squid-exporter` (Prometheus format) dan mengkonfigurasi New Relic Infrastructure Agent untuk melakukan scraping metrik tersebut. Ini memungkinkan pemantauan performa proxy (cache hits, koneksi, traffic) langsung dari dashboard New Relic.
*   **Log Forwarding**: Mengkonfigurasi Filebeat, Fluent Bit, atau New Relic Agent untuk mengirimkan `access.log` dan `cache.log` dari Squid langsung ke **New Relic Logs**, memungkinkan analisis traffic pattern dan error tracking terpusat.

## 2. Arsitektur & Deployment
*   **Containerized Support (Docker/Podman)**: Menyediakan `docker-compose.yml` dan `Dockerfile` pre-configured. Banyak modern environment lebih memilih menjalankan proxy sebagai container daripada di level OS/host.
*   **High Availability (HA) Setup**: Menyediakan panduan atau role Ansible tambahan untuk setup Keepalived (Virtual IP) atau HAProxy di depan beberapa instance Squid Proxy untuk konfigurasi Active-Passive atau Active-Active.

## 3. Network & Traffic Management
*   **Transparent Proxying (TPROXY)**: Menambahkan opsi untuk mengkonfigurasi rule `iptables` / `nftables` agar traffic dari client otomatis ter-route ke Squid tanpa perlu mereka men-set environment variable `https_proxy`. Sangat berguna untuk server yang tidak bisa dimodifikasi env vars-nya.
*   **Bandwidth Throttling (Delay Pools)**: Menambahkan konfigurasi untuk membatasi maksimum bandwidth (rate limiting) yang bisa dipakai oleh proxy, mencegah proxy menghabiskan kuota network environment lokal.

## 4. Security & Configuration
*   **Dynamic / External ACLs**: Memisahkan list allowed domains (`.newrelic.com`, dll) ke dalam file eksternal yang di-load secara dinamis oleh Squid, sehingga penambahan domain baru tidak selalu membutuhkan re-run Ansible playbook (`squid -k reconfigure` saja).
*   **Automated CA Rotation untuk SSL Bump**: Script pembantu untuk merotasi CA certificate jika sudah expired, dan mendistribusikannya kembali.
*   **LDAP / Active Directory Integration**: Selain Basic Auth (htpasswd), menambahkan support otentikasi yang terintegrasi langsung dengan enterprise Active Directory.

## 5. Script & CLI Enhancements
*   **Uninstall Script**: Menambahkan `uninstall.sh` atau playbook `teardown.yml` untuk menghapus instalasi Squid Proxy, membersihkan file konfigurasi, log, dan package dependencies secara bersih.
*   **Dry-run Mode**: Menambahkan flag `--dry-run` pada `install.sh` untuk mensimulasikan perubahan yang akan dilakukan Ansible sebelum mengekskusi.
