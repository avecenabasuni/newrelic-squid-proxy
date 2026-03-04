# Plan: New Relic Squid Proxy Testing

This document outlines a rapid, rigorous testing workflow specifically adapted for the Ansible-driven New Relic Squid Proxy project. It combines principles of **Test-Driven Development (TDD)**, **End-to-End (E2E) verification**, and safe **Deployment Procedures** to validate configuration and reliability before merging or deploying to production.

## Approach
Test the configuration layer (Ansible/Jinja2 output) first using synthetic validation. Follow this with End-to-End connectivity verifications inside an ephemeral container/VM simulating a user environment. Finally, utilize clear deployment and rollback checkpoints.

## Scope

- **In:** Ansible configuration generation formatting `squid.conf.j2`, proxy runtime start/stop testing, Region-Aware blocking logic, New Relic data ingestion routing, uninstallation sequence idempotency.
- **Out:** Load testing (performance limits), network hardware simulations, modification of native Squid C++ codebase.

## Action Items

### Phase 1: Static Analysis & Validation (Lint / Check)
*Based on `lint-and-validate` and `tdd` (Red/Green)*

- [ ] Add intentionally malformed YAML to `defaults/main.yml` and assert `yamllint` fails.
- [ ] Run `yamllint` on all `.yml`/`.yaml` files until completely green.
- [ ] Execute `ansible-lint site.yml` to identify and repair deprecated Ansible modules or syntactic anti-patterns.
- [ ] Run `shellcheck` against `install.sh` and `uninstall.sh`. 

### Phase 2: Configuration Syntax Unit Testing (TDD pattern)
*Based on `test-driven-development` and `deployment-procedures` Pre-deployment Checks*

- [ ] Execute `ansible-playbook site.yml --syntax-check` to catch compilation faults.
- [ ] Inject an invalid directive in `squid.conf.j2` (e.g. `invalid_param yes`) conceptually as the **RED** phase.
- [ ] Run `squid -k parse -f /etc/squid/squid.conf` to observe the failure explicitly.
- [ ] Revert `squid.conf.j2` to its legitimate state (**GREEN** phase) and verify `squid -k parse` yields zero syntax errors.
- [ ] Verify that `systemctl status squid` reaches an active, listening state (`ss -tulpn | grep 3128`).

### Phase 3: E2E Network Validation (Functional Testing)
*Based on `e2e-testing-patterns`*

- [ ] Send `curl -v -x http://localhost:3128 https://log-api.newrelic.com`; expect HTTP 200 via `CONNECT` tunnel.
- [ ] Apply **N1 (Region-Aware)** config restricting proxy to region `us`. Send curl via proxy to `https://log-api.eu.newrelic.com`; assert `HTTP 403 Forbidden` response from Squid. 
- [ ] Trigger **M5 (CA Rotation)** manually: run `/usr/local/bin/rotate-squid-ca.sh`.
  - Check timestamp of `/etc/squid/ssl_cert/proxy-ca.pem` has been updated.
  - Verify Squid seamlessly restarts and resumes MITM packet inspection logic.
- [ ] Trigger **N4 (Metrics)** local pull: run `curl -s http://localhost:3128/squid-internal-mgr/counters` and assert text output formatting is functional for the Flex agent. 

### Phase 4: Teardown & Rollback Readiness
*Based on `deployment-procedures` (Rollback & Clean State)*

- [ ] Initiate `sudo bash uninstall.sh` following a successful deployment test.
- [ ] Verify Squid service is stopped, disabled, and no lingering `/etc/squid` files exist.
- [ ] Verify that N-series and M-series artifacts (e.g., `/etc/newrelic-infra/*/squid*.yml`, tarballs, CA cron jobs) were completely eradicated.
- [ ] Re-run `install.sh` to effectively prove idempotency loop works flawlessly from zero.

## Open Questions

- What specific virtualization environment (e.g., Docker, Vagrant, AWS EC2) is mandated for running these E2E tests to mimic the target host OS (Ubuntu/RHEL)?
- Do we need a dedicated "dummy" New Relic License key to complete end-to-end integration visualization inside the New Relic dashboard?
