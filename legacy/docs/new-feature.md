# Future Enhancements & New Features Roadmap

> **Last updated**: March 5, 2026
> **Reference sources**: New Relic Network Docs & EOL Announcements

Feature roadmap to make `newrelic-squid-proxy` more robust and enterprise-ready, categorized by priority level for implementation planning.

---

## 🔴 High Priority
*Critical for POC success, enterprise compatibility, and core tool reliability.*

- [x] **SELinux / AppArmor Handling**
  - Fixes permission-denied issues on RHEL/SUSE. Auto-configures `squid_port_t` and `squid_cache_t`.
- [x] **Corporate Proxy Chaining (Cache Peer)**
  - Routes outbound traffic through a primary corporate proxy for servers without direct internet access.
- [x] **Region-Aware Configuration (US/EU)**
  - Filters allowed domains and connectivity tests based on the selected New Relic region.
- [x] **Uninstall Script**
  - `uninstall.sh` to cleanly remove all modifications with a single command.
- [ ] **Pre-flight System Check (B3-1)**
  - Validates disk space, DNS, port availability, and outbound reachability before starting.
- [ ] **Config Profiles (B3-2)**
  - `--profile minimal/standard/full` to skip interactive prompts for repeat users.
- [ ] **SSL Bump CA Distribution Helper (B3-3)**
  - Prints OS-specific commands to help clients trust the auto-generated Root CA.
- [ ] **GitHub Actions CI Matrix (B3-9)**
  - Automated tests across 6+ Linux distributions (Ubuntu, RHEL, openSUSE, etc.) on every PR.
- [ ] **Upgrade-in-Place (B3-5)**
  - `install.sh --upgrade` to update the tool and endpoint list without losing current config.

---

## 🟡 Medium Priority
*Enhances operational stability, observability, and open-source quality.*

- [x] **Log Forwarding (NR Infra Agent)**
  - Forwards Squid `access.log` and `cache.log` to New Relic Logs.
- [x] **Squid Metrics via NR Flex Integration**
  - Custom `nri-flex` config to pull real-time metrics (hit ratio, connections, etc.) into NR.
- [x] **One-Click Diagnostic Archive**
  - `support-bundle.sh` to package logs/configs for troubleshooting.
- [x] **Automated CA Rotation for SSL Bump**
  - Automatically rotates root CA SSL bump certificates via cron to prevent downtime.
- [x] **Dry-run Mode**
  - `bash install.sh --dry-run` using Ansible `--check` to preview changes safely.
- [x] **Proxy Config Snippet Generator**
  - Prints ready-to-copy config for NR Infra Agent, Java, Python, Node.js, and .NET.
- [x] **Firewall Auto-Open**
  - Detects `ufw`/`firewalld`/`iptables` and offers to open the proxy port automatically.
- [ ] **NR Alert on Verification Failure (B3-6)**
  - Sends a custom `SquidVerifyFailed` event to New Relic if endpoints become unreachable.
- [ ] **Ansible Galaxy Role Publishing (B3-10)**
  - Restructures the role for distribution via `ansible-galaxy install`.
- [ ] **Dashboard Auto-Import via NerdGraph (B3-11)**
  - Uses the NR API to automatically upload the monitoring dashboard post-install.
- [ ] **Contributing Guide & Issue Templates (B3-12)**
  - Adds `CONTRIBUTING.md` and repo standard templates for bugs/features.
- [ ] **Log Rotation Configuration (B3-7)**
  - Standardizes 7-day retention and compression for Squid logs to prevent disk-full errors.
- [ ] **Endpoint Drift Detection (B3-8)**
  - Checksum-based warning if the deployed whitelist is outdated vs the latest known endpoints.
- [ ] **Proxy Chain Pre-Validation (B3-4)**
  - Tests connectivity through the corporate proxy *before* finalizing the configuration.

---

## 🔵 Low Priority
*Non-blocking features, performance baselining, and niche use cases.*

- [ ] **Scheduled Verify Cron (N8)**
  - Nightly verification checks to detect unannounced New Relic endpoint changes.
- [ ] **Config Backup Before Changes (N5)**
  - Automatic timestamped backups of `/etc/squid/` before every Ansible run.
- [ ] **Dualstack Endpoints Support**
  - Future-proofing to support New Relic's IPv6 (HTTP/3) allowed domains.
- [ ] **Containerized Support (Docker/Podman)**
  - Host-level deployment remains the priority, but container support is planned for lab environments.
- [ ] **Health Check Endpoint**
  - HTTP `/healthz` for Load Balancers and NR Synthetics monitoring.
- [ ] **Proxy Performance Baseline**
  - Record round-trip latency through the proxy post-install as a baseline.

---

## 🧬 Investigative / Dropped
- [ ] **Transparent Proxying (TPROXY)**
  - *Status: High Risk.* May disrupt enterprise routing via iptables/nftables.
- [ ] **LDAP / Active Directory Integration**
  - *Status: Niche.* Significant dependency overhead for POC scope.
- [ ] **High Availability (Keepalived / HAProxy)**
  - *Status: Overkill.* Most POCs target single-node egress.
- [~] **Agent Auto-Configuration Tool**
  - *Status: Dropped.* APM agents rarely sit on the same host as the proxy.
