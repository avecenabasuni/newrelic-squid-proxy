# Plan: Squid Proxy Automation for New Relic via Shell + Ansible

> **This document is the primary reference for the agentic IDE (Google Antigravity) to build the project autonomously.**
> Each requirement has an explicit "done" definition so the agent can self-verify without needing feedback.

---

## 1. Problem Statement

When conducting a Proof of Concept (POC) for New Relic, customers often require a **forward proxy** to access New Relic endpoints from servers without direct internet access. Currently, the installation and configuration of Squid Proxy are performed manually using pure shell scripts—which are prone to:

- **Lack of Idempotency** — running the script twice can break the configuration.
- **Hard-coded Configurations** — toggling features (SSL Bump, Auth) requires manual file edits.
- **Unstructured Code** — a single monolithic shell file handles OS detection, package installation, config templating, and service management.
- **Weak Error Handling** — race conditions in background processes (`$?` vs `wait`).

**Solution**: Rebuild the project using a **shell bootstrap (`install.sh`) + Ansible playbook** architecture, where:
- Shell handles lightweight bootstrapping (OS detection, Ansible installation, interactive prompts).
- Ansible handles complex configurations idempotently (templating, packages, services, validation).

---

## 2. Goals & Non-Goals

### Goals (MVP)
| # | Goal | Description |
|---|------|-------------|
| G1 | One-liner Install | `curl -sSL <URL>/install.sh \| bash` must be sufficient to install & configure everything. |
| G2 | Multi-distro Linux | Support apt (Ubuntu/Debian), yum (CentOS/RHEL 7), dnf (RHEL 8+/Fedora/Rocky/Alma), and zypper (SLES). |
| G3 | SSL Bump Toggle | Enable/disable via prompt, automatically generating the correct config. |
| G4 | Basic Auth Toggle | Enable/disable via prompt, with passwords automatically hashed via `htpasswd`. |
| G5 | Repo Access | The proxy MUST NOT block access to the OS package repositories. |
| G6 | Automated Verification | After installation, connectivity to all New Relic endpoints is verified automatically. |
| G7 | Idempotency | Re-running `install.sh` does not break valid existing configurations. |

### Non-Goals
| # | Non-Goal | Reason |
|---|----------|--------|
| NG1 | Windows Support | Scoped out of MVP — Squid on Windows is too niche. |
| NG2 | Multi-host Deploy | MVP always installs to localhost — remote deployment can be added later. |
| NG3 | GUI / Web UI | Overkill for POC use cases. |
| NG4 | Container/Docker | Customer POCs usually use bare-metal VMs rather than containers. |

---

## 3. Tech Stack & Rationale

| Layer | Technology | Minimum Version | Rationale |
|-------|------------|-----------------|-----------|
| **Bootstrap** | Bash (`install.sh`) | bash 4+ | Zero dependencies — every Linux has bash. Ideal for OS detection, Ansible installation, and interactive prompts. |
| **Config Management** | Ansible (`ansible-core`) | **>= 2.14** | Idempotent, declarative, Jinja2 templating, multi-distro package abstraction (`ansible.builtin.package`), and built-in config validation. Version 2.14+ chosen for stability and wide availability. |
| **Templating** | Jinja2 (via Ansible) | — | Conditional blocks for SSL Bump & Auth — one `squid.conf.j2` template generates all config variants. |
| **Verification** | `ansible.builtin.uri` | — | HTTP requests to New Relic endpoints directly from the playbook, providing structured results (not text grep). |
| **Auth Hashing** | `htpasswd` CLI (via `ansible.builtin.command`) | — | More portable than `community.general.htpasswd` module — zero extra collections required, only needs `apache2-utils` / `httpd-tools` (installed as dependencies). |

> [!IMPORTANT]
> **Ansible Collection Policy**: This project ONLY uses `ansible.builtin.*` modules — no dependencies on `community.general` or other collections. This ensures `ansible-core` is sufficient without needing `ansible-galaxy`.

### Why Shell + Ansible, not Shell only?

```
┌─────────────────────────────────────────────────────────────────┐
│                    DIVISION OF RESPONSIBILITY                   │
├────────────────────────┬────────────────────────────────────────┤
│ install.sh (Shell)     │ Ansible Playbook                       │
├────────────────────────┼────────────────────────────────────────┤
│ ✔ Detect OS & pkg mgr  │ ✔ Install Squid (idempotent)           │
│ ✔ Install Ansible      │ ✔ Template squid.conf.j2               │
│ ✔ Interactive prompts  │ ✔ Manage SSL cert directory            │
│ ✔ Generate variables   │ ✔ Create htpasswd file                 │
│ ✔ Trigger playbook     │ ✔ Service enable/restart               │
│                        │ ✔ Config validation (squid -k parse)   │
│                        │ ✔ Endpoint verification (uri module)   │
└────────────────────────┴────────────────────────────────────────┘
```

- **Shell** excels at: lightweight bootstrapping without dependencies, user prompts (`read -p`), and single-file downloads.
- **Ansible** excels at: idempotent configuration management, Jinja2 templating with conditionals, multi-distro package abstraction, and structured verification output.

---

## 4. Bootstrap & UX Flow

### Entry Point
```bash
curl -sSL https://raw.githubusercontent.com/avecenabasuni/newrelic-squid-proxy/main/install.sh | bash
```

### 4.1 Repository Download Strategy (Critical Design Decision)

> [!IMPORTANT]
> **Problem**: `install.sh` is run via `curl | bash` — meaning only `install.sh` is in memory during execution. All Ansible files (playbook, roles, templates) are not yet on disk. The script must download the **complete** repository before running Ansible.

**Solution**: `install.sh` has `REPO_URL` and `REPO_BRANCH` variables hardcoded at the top, which can be overridden via environment variables.

```bash
# ─── Configurable Repository Source ───────────────────────────────
# Override via environment variables if the repo URL changes or for a fork:
#   REPO_URL=https://github.com/my-fork/newrelic-squid-proxy.git bash install.sh
REPO_URL="${REPO_URL:-https://github.com/avecenabasuni/newrelic-squid-proxy.git}"
REPO_BRANCH="${REPO_BRANCH:-main}"
INSTALL_DIR="/opt/newrelic-squid-proxy"
```

**Download Strategy (3-tier fallback)**:

```
┌─────────────────────────────────────────────────────────────────┐
│                  REPO DOWNLOAD STRATEGY                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Priority 1: Check if $INSTALL_DIR exists & is valid            │
│  ├─ YES + site.yml exists → Skip download, use existing         │
│  │   (supports manual clone scenario followed by install run)    │
│  └─ NO → Proceed to Priority 2                                   │
│                                                                 │
│  Priority 2: git clone (if git is available)                    │
│  ├─ git clone --depth 1 --branch $REPO_BRANCH $REPO_URL         │
│  │   $INSTALL_DIR                                               │
│  └─ FAILED → Proceed to Priority 3                              │
│                                                                 │
│  Priority 3: curl/wget download tarball from GitHub             │
│  ├─ URL: ${REPO_URL%.git}/archive/refs/heads/${REPO_BRANCH}.tar.gz │
│  ├─ Extract to /tmp, then move to $INSTALL_DIR                  │
│  └─ FAILED → exit 1 "Cannot download repository"                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Why three tiers?**
- **Tier 1 (local check)**: Supports users who manually `git clone` first — common in environments restricting `curl | bash`.
- **Tier 2 (git clone)**: Most reliable, shallow clones save bandwidth, no history needed.
- **Tier 3 (tarball)**: Fallback for servers without git — GitHub provides predictable tarball URLs.

**Acceptance Criteria for Download Mechanism**:
- [ ] `REPO_URL` and `REPO_BRANCH` variables can be overridden via env vars.
- [ ] If `$INSTALL_DIR/site.yml` exists, skip download and display "Using existing installation".
- [ ] If git is available, use a shallow clone to `$INSTALL_DIR`.
- [ ] If git is not available, download the tarball via curl (or wget).
- [ ] If all download methods fail, exit 1 with a clear error message.
- [ ] After download, validate that `$INSTALL_DIR/site.yml` exists.

**Definition of Done**: After step 5 finishes, `ls $INSTALL_DIR/site.yml` returns exit code `0`.

### 4.2 Flow Diagram

```
┌──────────────────────────────────────────────────────────────────┐
│                         install.sh                               │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. Banner + metadata                                            │
│  2. Check: running as root / sudo?                               │
│     └─ NO → exit 1 with error message                            │
│  3. Detect OS & package manager                                  │
│     ├─ /etc/os-release → ID, VERSION_ID                          │
│     ├─ Map: ubuntu/debian → apt                                  │
│     │       centos/rhel 7 → yum                                  │
│     │       rocky/alma/rhel 8+/fedora → dnf                      │
│     │       sles/opensuse → zypper                               │
│     └─ UNKNOWN → exit 1                                          │
│  4. Install Ansible if not already present                       │
│     ├─ command -v ansible-playbook                               │
│     ├─ Check version: ansible --version >= 2.14                  │
│     ├─ apt: apt install -y ansible                               │
│     ├─ yum: yum install -y epel-release && yum install ansible   │
│     ├─ dnf: dnf install -y ansible-core                          │
│     ├─ zypper: zypper install -y ansible                         │
│     └─ Fallback: pip3 install ansible-core                       │
│  5. Download/clone repository to $INSTALL_DIR                    │
│     ├─ Check: Does $INSTALL_DIR/site.yml exist? → skip           │
│     ├─ If git available: git clone --depth 1 (shallow)           │
│     ├─ Fallback: curl download tarball + extract                 │
│     └─ Validation: $INSTALL_DIR/site.yml must exist              │
│  6. Interactive prompts                                          │
│     ├─ Proxy port? [default: 3128]                               │
│     ├─ Enable SSL Bump? (y/n) [default: n]                       │
│     │   └─ YES: path CA cert? path CA key?                       │
│     ├─ Enable Basic Auth? (y/n) [default: n]                     │
│     │   └─ YES: username? password? (read -s)                    │
│     └─ Confirm summary → proceed?                                │
│  7. Generate extra-vars JSON → /tmp/nr-squid-vars.json           │
│  8. cd $INSTALL_DIR && Run:                                      │
│     ansible-playbook site.yml --extra-vars @/tmp/nr-squid-vars.json │
│  9. Run: ansible-playbook verify.yml                             │
│          --extra-vars @/tmp/nr-squid-vars.json                    │
│ 10. Cleanup: rm -f /tmp/nr-squid-vars.json                       │
│ 11. Print summary & proxy usage instructions                     │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

### Prompt Summary (Before Execution)

The script should display a configuration summary before running Ansible, for example:

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

**Description**: `install.sh` detects the Linux distribution and package manager, then installs Ansible (`ansible-core >= 2.14`) if it's not already available.

**Acceptance Criteria**:
- [ ] Script reads `/etc/os-release` and determines `PKG_MANAGER` (apt/yum/dnf/zypper).
- [ ] If `ansible-playbook` exists in `$PATH` AND version is >= 2.14, skip Ansible installation.
- [ ] If Ansible is missing or the version is too old, install using the detected package manager.
- [ ] Fallback: if the package manager fails, try `pip3 install ansible-core`.
- [ ] If the OS is unsupported, exit with code `1` and a descriptive error message.

**Definition of Done**: After `install.sh` finishes step 4, `ansible-playbook --version` returns exit code `0` and shows version >= 2.14.

---

### F2: Interactive Prompts & Variable Generation

**Description**: The script collects configuration from the user via interactive prompts and generates a JSON file for Ansible extra-vars.

**Acceptance Criteria**:
- [ ] Prompt for proxy port, default `3128`.
- [ ] Prompt for SSL Bump (y/n), default `n`.
  - [ ] If `y`: prompt for CA cert and key paths, validating file existence.
- [ ] Prompt for Basic Auth (y/n), default `n`.
  - [ ] If `y`: prompt for username and password (password hidden during input).
- [ ] Display a confirmation summary before execution.
- [ ] Generate `/tmp/nr-squid-vars.json` in the specified format:

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

**Definition of Done**: `/tmp/nr-squid-vars.json` contains valid JSON matching user input; `python3 -m json.tool /tmp/nr-squid-vars.json` returns exit code `0`.

---

### F3: Ansible Role — Squid Installation (Multi-Distro)

**Description**: The `squid_proxy` role installs Squid and its dependencies idempotently using `ansible.builtin.package`.

**Acceptance Criteria**:
- [ ] Squid is installed on all target distributions via `ansible.builtin.package`.
- [ ] Auth tools package is installed: `apache2-utils` (Debian/Ubuntu) or `httpd-tools` (RHEL family).
- [ ] Tasks are idempotent: running the playbook twice results in `changed=0` on the second run.

**Definition of Done**: `squid -v` returns exit code `0` and shows the Squid version. Playbook second run shows all tasks as `ok`, not `changed`.

---

### F4: Jinja2 Template — `squid.conf.j2`

**Description**: A single Jinja2 template that generates the complete Squid configuration based on variables, replacing legacy static files.

**Acceptance Criteria**:
- [ ] Template generates network/port blocks with RFC1918 subnets.
- [ ] Domain whitelist includes all New Relic endpoints (US + EU) + OS repo domains.
- [ ] SSL Bump block only appears if `ssl_bump_enabled: true`.
  - [ ] Port `3129` listening with cert/key paths from variables.
  - [ ] SSL Bump steps (peek → bump New Relic → splice all).
  - [ ] Outgoing TLS minimum 1.2.
- [ ] Basic Auth block only appears if `basic_auth_enabled: true`.
  - [ ] `auth_param` and `acl authenticated_users` are rendered.
  - [ ] Access policy changes: `http_access allow authenticated_users localnet allowed_domains`.
- [ ] Logging, caching, privacy, and coredump blocks are always present.
- [ ] Proxy port uses the `{{ squid_port }}` variable.

**Definition of Done**: `squid -k parse -f /etc/squid/squid.conf` returns exit code `0` (valid config) for all toggle combinations:
1. SSL Bump OFF, Auth OFF
2. SSL Bump ON, Auth OFF
3. SSL Bump OFF, Auth ON
4. SSL Bump ON, Auth ON

---

### F5: SSL Bump Setup

**Description**: If SSL Bump is enabled, Ansible prepares the certificate directory and SSL DB.

**Acceptance Criteria**:
- [ ] `/etc/squid/ssl_cert/` directory created with `700` permissions, owner `proxy` (or distro-specific user).
- [ ] CA cert & key are copied to `/etc/squid/ssl_cert/` from the user-provided path.
- [ ] SSL DB initialized: `/var/lib/squid/ssl_db` via `security_file_certgen`.
  - [ ] `security_file_certgen` path is detected automatically based on the distro.
- [ ] Task skipped if `ssl_bump_enabled: false`.

**Definition of Done**: CA cert and key files exist in `/etc/squid/ssl_cert/`, permissions are correct, and `ls -la /var/lib/squid/ssl_db/` shows a valid DB. If SSL Bump is OFF, tasks are `skipped`.

---

### F6: Basic Auth Setup

**Description**: If Basic Auth is enabled, Ansible creates the htpasswd file and configures Squid.

> [!NOTE]
> **Decision**: Use `ansible.builtin.command` + `htpasswd` CLI instead of `community.general.htpasswd` module for portability (zero extra dependencies).

**Acceptance Criteria**:
- [ ] `/etc/squid/passwords` file created with `640` permissions, owned by `{{ squid_user }}:{{ squid_group }}`.
- [ ] Password hashed using `htpasswd` CLI.
- [ ] Task is idempotent: check if user exists before running `htpasswd`.
- [ ] Access without credentials returns HTTP `407 Proxy Authentication Required`.
- [ ] Access with valid credentials works normally.
- [ ] Task skipped if `basic_auth_enabled: false`.

**Definition of Done**:
- `curl -x http://localhost:{{ squid_port }} https://newrelic.com` returns `407`.
- `curl -x http://user:pass@localhost:{{ squid_port }} https://newrelic.com` returns `200/301`.
- If Auth is OFF: `curl -x http://localhost:{{ squid_port }} https://newrelic.com` returns `200/301` without credentials.

---

### F7: Service Management

**Description**: Ansible manages the Squid service — config validation, restarting, and enabling at boot.

**Acceptance Criteria**:
- [ ] Config validated before restart via handler: `squid -k parse`.
- [ ] Squid restarted only if config changes (triggered by template task notify).
- [ ] Squid enabled to start at boot: `systemctl enable squid`.
- [ ] Squid status checked: `systemctl is-active squid` returns `active`.

**Definition of Done**: `systemctl is-active squid` returns `active` and `systemctl is-enabled squid` returns `enabled`.

---

### F8: Endpoint Verification (Automated)

**Description**: The `verify.yml` playbook tests connectivity to all New Relic endpoints through the new proxy.

**Acceptance Criteria**:
- [ ] Tests at least 32 endpoints (US + EU) from `newrelic_endpoints`.
- [ ] Uses `ansible.builtin.uri` with proxy simulation via environment variables.
- [ ] HTTP status `200`, `301`, `400`, or `404` are considered successful.
- [ ] Results displayed as a summary: total success vs failed.
- [ ] Includes credentials if basic auth is active.

**Definition of Done**: Playbook output shows summary: `Verification complete: 32/32 endpoints reachable`. List failed endpoints if any.

---

## 6. Project File Structure

```
newrelic-squid-proxy/
├── install.sh                          # Bootstrap: detect OS, install Ansible, prompts, run playbook
├── ansible.cfg                         # Ansible config (local, no SSH)
├── inventory/
│   └── localhost.ini                   # Static inventory → localhost connection=local
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
├── legacy/                             # Legacy files kept as reference
│   ├── squid.conf                      # Old static config
│   ├── squid-ssl-bump.conf             # Old SSL Bump config
│   ├── newrelic-squid-proxy.sh          # Old install script
│   └── newrelic-endpoint-test.sh        # Old endpoint test script
├── .gitignore
├── LICENSE
├── plan-squid-proxy.md                 # This planning document
└── README.md                           # Updated documentation
```

---

## 7. Configuration Variables

(Refer to the respective `defaults/main.yml` and `vars/*.yml` files for current variable definitions.)

---

## 8. Technical Risks & Mitigation

| # | Risk | Impact | Mitigation |
|---|------|--------|------------|
| R1 | Ansible not in OS repo | Bootstrap fails | Add fallback: install via `pip3 install ansible`. |
| R2 | Certgen path varies | SSL Bump fails | Auto-detect path or use OS family-specific variables. |
| R3 | Port conflict | Squid fails to start | Add pre-check: `ss -tlnp` and warn user if port is occupied. |
| R4 | Firewall blocked | Proxy unreachable | Document in README (manual step to keep script non-invasive). |

---

## 9. Open Questions

- All architectural and implementation questions have been **RESOLVED** and integrated into the plan above.

---

## 10. Verification Plan

### 10.1 Automated Tests (via `verify.yml`)

1. Squid service running.
2. Squid config syntax valid.
3. Port listening.
4. NR endpoints reachable (Success rate 100%).
5. Authentication required return 407 (when enabled).
6. Idempotency test (Run twice, expect `changed=0`).

### 10.2 Manual Verification

1. `systemctl status squid` → Active.
2. `curl -x http://localhost:3128 https://newrelic.com` → 200/301.
3. `curl -x http://localhost:3128 https://google.com` → 403 (Denied).
4. `curl -x http://localhost:3129 https://newrelic.com` → 200 with MITM cert (SSL Bump ON).
