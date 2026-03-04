# Future Enhancements & New Features Roadmap

> **Last updated**: March 4, 2026
> **Reference sources**: New Relic Network Docs & EOL Announcements

Feature roadmap to make `newrelic-squid-proxy` more robust and enterprise-ready, ordered by priority and relevance for New Relic POC execution.

---

## High Priority - COMPLETED

*Directly relevant for resolving operational blockers in many enterprise environments during POC.*

- [x] **P1: SELinux / AppArmor Handling**
  - Major blocker in RHEL-based distros. Without the correct SELinux context (`squid_port_t`, `squid_cache_t`), Squid may fail to start.
  - Implementation: `roles/squid_proxy/tasks/selinux.yml`
- [x] **P2: Corporate Proxy Chaining (Cache Peer)**
  - For enterprises where local servers do not have direct internet access. This proxy routes outbound traffic through a primary corporate proxy.
  - Implementation: Interactive prompt in `install.sh`, `cache_peer` template in `squid.conf.j2`
- [x] **P3: Uninstall Script**
  - For clean POC evaluations. Engineers can remove all modifications with a single command.
  - Implementation: `uninstall.sh` (standalone) + `teardown.yml` (Ansible playbook)
- [x] **P4: Dry-run Mode**
  - Standard practice for shell script installers. Increases trust for customer security teams.
  - Implementation: `bash install.sh --dry-run` (Ansible `--check --diff`)

---

## Medium Priority - PARTIALLY COMPLETED

*Highly recommended for operational stability and troubleshooting post-initial POC.*

- [x] **M1: Dynamic / External ACLs**
  - Separates the allowed domains list into an external file (`/etc/squid/allowed_domains.txt`) that can be reloaded by Squid without re-running Ansible.
  - Implementation: `allowed_domains.txt.j2`, `dynamic_acl.yml`, `Reconfigure Squid` handler
- [x] **M2: Log Forwarding (NR Infra Agent)**
  - Forwards Squid `access.log` and `cache.log` to New Relic Logs via the NR Infrastructure Agent (embedded Fluent Bit).
  - Implementation: `nr-logging.yml.j2`, `log_forwarding.yml`, `log_forwarding_enabled` variable
- [x] **M3: One-Click Diagnostic Archive**
  - Script to automatically package configurations, logs, and test results into a `.tar.gz`. Reduces back-and-forth escalation during network issues.
  - Implementation: `support-bundle.sh`
- [~] ~~**M4: Agent Auto-Configuration Tool**~~ *(Dropped)*
  - Reason for dropping: Proxy hosts are usually dedicated nodes with internet access. APM agents are rarely installed on the same host as the proxy.
- [x] **M5: Automated CA Rotation for SSL Bump**
  - Automatically handles root CA SSL bump rotation when nearing expiration to prevent downtime. Implemented via the `rotate-squid-ca.sh` cron script.

---

## New Features (Brainstorm Batch 2)

*Additional features from brainstorming, ordered by impact-to-effort ratio.*

### High Priority

- [x] **N1: Region-Aware Configuration (US/EU)**
  - Currently, all 32+ endpoints (US + EU) are whitelisted and tested. In strict environments, customers only want to whitelist their specific region.
  - Solution: Add "Which NR region? [1] US [2] EU [3] Both (default)" prompt to `install.sh`. Domain whitelist and verification are automatically filtered by region.
  - Effort: Low | Value: High
- [x] **N2: Firewall Auto-Open**
  - Most common issue after install: traffic still fails because the port wasn't opened in the local firewall.
  - Solution: Detect `ufw`/`firewalld`/`iptables` and offer to open the proxy port at the end of installation.
  - Effort: Low | Value: High
- [x] **N3: Proxy Config Snippet Generator**
  - Post-install summary only shows `export https_proxy=...`. SEs have to manually find how to set proxies for each NR agent.
  - Solution: Generate and display ready-to-copy config snippets for NR Infra Agent (`newrelic-infra.yml`), Java APM (`-D` JVM args), Python APM (`newrelic.ini`), Node.js (`env`), and .NET (`newrelic.config`).
  - Effort: Low | Value: High
- [x] **N4: Squid Metrics Monitoring via NR Flex Integration**
  - The standard Infra agent doesn't natively pull custom metrics from Squid unless via Prometheus/JMX, but Squid has a default cache manager.
  - Solution: Deploy a custom `nri-flex` config (`squid-metrics-flex.yml`) if `nr_integration_enabled=true` that performs HTTP GET polling to `/squid-internal-mgr/counters` and breaks it down into New Relic metrics.
  - Effort: Medium | Value: High
  - Metrics exposed:
    - `squid.requests_per_second` - Request rate
    - `squid.cache_hit_ratio` - Percentage of requests served from cache
    - `squid.active_connections` - Current client connections
    - `squid.memory_usage_mb` - Squid process memory
    - `squid.dns_median_svc_time` - DNS lookup latency
    - `squid.http_errors_count` - Error response count
  - Effort: Medium | Value: High

### Medium Priority

- [ ] **N5: Config Backup Before Changes**
  - Every Ansible run automatically backups `/etc/squid/` to `/etc/squid/backup.YYYYMMDD_HHMMSS/`. If an error occurs, admins can rollback manually.
  - Effort: Low | Value: Medium
- [ ] **N6: Install Audit Log**
  - Pipe all `install.sh` output to `/var/log/nr-squid-install.log`. For enterprise compliance audits needing proof of execution.
  - Effort: Low | Value: Medium
- [ ] **N7: Access Log Quick Parser (`squid-report.sh`)**
  - CLI helper displaying: Top 10 blocked domains, Error count by HTTP code, and Slowest requests. Purely `awk`-based, no additional dependencies.
  - Effort: Low | Value: Medium
- [ ] **N8: Scheduled Verify Cron**
  - Optional cron job that runs `verify.yml` nightly and logs results. Detects if NR changes endpoints without notice.
  - Effort: Medium | Value: Medium

### Low Priority

- [ ] **N9: Health Check Endpoint**
  - HTTP `/healthz` endpoint via Squid `cachemgr.cgi` returning 200 if Squid is healthy. Useful for Load Balancers and NR Synthetics monitoring.
  - Effort: Medium | Value: Low (niche)
- [ ] **N10: Proxy Performance Baseline**
  - Record round-trip latency through the proxy post-install as a baseline. Reference for future "proxy is slow" complaints.
  - Effort: Medium | Value: Low

---

## Low Priority / Niche

*Advanced features for long-term deployment or specific use cases, non-blocking for POC.*

- [ ] **Containerized Support (Docker/Podman)**
  - Provide a container version. Conflicts with the MVP goal of focusing on host-level deployment.
- [ ] **High Availability (Keepalived / HAProxy)**
  - Setup active-active load balancing. Overkill for POC.
- [ ] **Bandwidth Throttling (Delay Pools)**
  - QoS to limit internet bandwidth used by NR agents. Rarely a requirement.
- [ ] **LDAP / Active Directory Integration**
  - Enterprise identity provider integration for proxy authentication. Requires significant dependencies.
- [ ] **Synthetics Job Manager (SJM) Profiles**
  - Configuration presets for SJM-specific network needs. *(CPM went EOL on October 22, 2024)*.
- [ ] **Dualstack Endpoints Support**
  - Future-proofing to support New Relic's IPv6 (HTTP/3) allowed domains.
- [ ] **Companion Health Check API & Web GUI**
  - Web UI / API service to manage allowed domains without the CLI, and endpoint testing for Load Balancer health checks.

---

## Environment Validation Needed

*Operational ideas that are potentially destructive or heavily dependent on the target OS defaults.*

- [ ] **Transparent Proxying (TPROXY)**
  - Risk: Modifying iptables/nftables to automatically route HTTP/S traffic through the proxy could disrupt enterprise internal routing.
- [ ] **Squid SNMP Metrics Exporter**
  - Risk: Default distro Squid packages are often compiled **without** the `--enable-snmp` flag. Must be manually verified (`squid -v | grep snmp`) before deployment. Safer alternative: use N4 (Flex Integration via `squidclient`).
