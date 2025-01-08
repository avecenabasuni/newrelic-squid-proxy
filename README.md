# Setup New Relic Squid Proxy

Panduan ini akan membawa Anda melalui proses pengaturan **New Relic Squid Proxy**, termasuk cara mengunduh dan menjalankan script untuk menginstal Squid Proxy serta menguji endpoint.

## Persyaratan

Sebelum memulai, pastikan Anda memiliki hal-hal berikut:
- `curl` atau `wget` (untuk mengunduh script)
- `bash` (untuk mengeksekusi script)
- Akses root atau `sudo` pada server

## Langkah-Langkah Mengatur New Relic Squid Proxy

### Step 1: Download Script
Anda dapat mengunduh script untuk pengujian endpoint dan instalasi Squid Proxy menggunakan `curl` atau `wget`.

#### Menggunakan `curl`:
1. **Untuk pengujian endpoint** (menjalankan test endpoint):
```bash
curl -o newrelic-endpoint-test.sh https://raw.githubusercontent.com/avecenabasuni/newrelic-squid-proxy/refs/heads/main/newrelic-endpoint-test.sh
```

2. **Untuk instalasi Squid Proxy** (install Squid Proxy):
```bash
curl -o newrelic-squid-proxy.sh https://raw.githubusercontent.com/avecenabasuni/newrelic-squid-proxy/refs/heads/main/newrelic-squid-proxy.sh
```
#### Menggunakan `wget`:
Alternatif lainnya, Anda bisa menggunakan `wget` untuk mengunduh script:
1. **Untuk pengujian endpoint**:
```bash
wget https://raw.githubusercontent.com/avecenabasuni/newrelic-squid-proxy/refs/heads/main/newrelic-endpoint-test.sh -O newrelic-endpoint-test.sh
```

3. **Untuk instalasi Squid Proxy**:
```bash
wget https://raw.githubusercontent.com/avecenabasuni/newrelic-squid-proxy/refs/heads/main/newrelic-squid-proxy.sh -O newrelic-squid-proxy.sh
```

### Step 2: Beri Izin Eksekusi pada Script
Setelah script diunduh, Anda perlu memberikan izin agar script dapat dieksekusi. Jalankan perintah berikut:
```bash
chmod +x newrelic-endpoint-test.sh chmod +x newrelic-squid-proxy.sh
```

### Step 3: Jalankan Script

Sekarang, Anda dapat menjalankan script untuk menguji endpoint dan menginstal Squid Proxy.
1. **Untuk menguji endpoint New Relic**:
```bash
./newrelic-endpoint-test.sh`
```

2. **Untuk menginstal Squid Proxy**:
```bash
./newrelic-squid-proxy.sh
```

Ikuti instruksi yang ditampilkan di layar untuk menyelesaikan pengaturan.

## Troubleshooting

- **Error Izin**: Jika Anda mengalami kesalahan izin, pastikan Anda menjalankan script dengan hak akses yang cukup (gunakan `sudo` jika diperlukan).
- **File Tidak Ditemukan**: Jika script tidak ditemukan, periksa kembali URL yang Anda gunakan untuk mengunduh script.
- **Masalah Eksekusi**: Pastikan script memiliki izin eksekusi (`chmod +x`).

## Catatan Tambahan
- Anda bisa memperbarui script dengan mengunduh versi terbaru dari repositori.
- Untuk informasi lebih lanjut tentang konfigurasi New Relic atau Squid Proxy, silakan merujuk ke dokumentasi resmi mereka.
