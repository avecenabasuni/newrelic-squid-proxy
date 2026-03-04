# New Relic Squid Proxy

Automated installation and configuration of **Squid Proxy** to support New Relic POCs in environments requiring a forward proxy.

## Features

- **One-liner install** - `curl -sSL <URL>/install.sh | sudo bash`
- **Multi-distro** - Ubuntu, Debian, CentOS, RHEL, Rocky, Alma, Fedora, SLES, openSUSE
- **SSL Bump (optional)** - MITM interception for TLS traffic to New Relic
- **Basic Auth (optional)** - Proxy authentication via htpasswd
- **Cache Peer (optional)** - Corporate proxy chaining for environments without direct internet access
- **Domain whitelist** - Only allows access to New Relic endpoints + OS package repositories
- **Dynamic ACLs** - Domain list in an external file, can be reloaded without restart (`squid -k reconfigure`)
- **Log Forwarding** - Forward `access.log` and `cache.log` to New Relic Logs via NR Infrastructure Agent
- **SELinux support** - Auto-configures SELinux booleans and contexts on RHEL-based systems
- **Dry-run mode** - Preview all changes without applying them (`--dry-run`)
- **Uninstall script** - Remove all components with a single command
- **Support bundle** - Diagnostic archive for troubleshooting (`support-bundle.sh`)
- **Automated verification** - Automatically tests connection to 32+ New Relic endpoints (US + EU)
- **Idempotent** - Safe to run multiple times

## Quick Start

### Automated Installation (Recommended)

```bash
curl -sSL https://raw.githubusercontent.com/avecenabasuni/newrelic-squid-proxy/main/install.sh | sudo bash
```

The script will automatically:

1. Detect OS and package manager
2. Install Ansible if not present
3. Display interactive configuration prompts
4. Install and configure Squid Proxy
5. Run connection verification to all New Relic endpoints

### Manual Installation

```bash
# Clone repository
git clone https://github.com/avecenabasuni/newrelic-squid-proxy.git
cd newrelic-squid-proxy

# Run installer
sudo bash install.sh
```

### Dry-run (Preview Without Applying)

```bash
sudo bash install.sh --dry-run
```

Ansible is run with `--check --diff` so no packages are installed and no configurations are modified.

### Override Repository URL

```bash
REPO_URL=https://github.com/my-fork/newrelic-squid-proxy.git bash install.sh
```

## Configuration

All configuration is handled via interactive prompts during installation:

| Parameter | Default | Description |
| --------- | ------- | ----------- |
| Proxy Port | `3128` | HTTP proxy port |
| NR Region | `us` | Select New Relic data region (us/eu/both) for ACL filtering |
| SSL Bump | `disabled` | Enable MITM interception (provide existing CA cert or auto-generate with rotation) |
| Basic Auth | `disabled` | Enable proxy authentication (requires username & password) |
| Cache Peer | `disabled` | Enable corporate proxy chaining (requires host & port of upstream proxy) |
| NR Integration | `disabled` | Deploy Log forwarding & NRI-Flex Metrics monitor in NR Infra agent |

## Proxy Usage

### Without Authentication

```bash
export https_proxy=http://<proxy-host>:3128
curl https://newrelic.com
```

### With Authentication

```bash
export https_proxy=http://username:password@<proxy-host>:3128
curl https://newrelic.com
```

### Set Proxy for New Relic Agent

```bash
# Add to environment or agent configuration
export NEW_RELIC_PROXY_HOST=<proxy-host>
export NEW_RELIC_PROXY_PORT=3128
```

## Dynamic ACL (Add Domains Without Restart)

The domain whitelist is stored in `/etc/squid/allowed_domains.txt`. To add a new domain:

```bash
# Add domain
echo ".api.newrelic.com" >> /etc/squid/allowed_domains.txt

# Reload configuration (no restart, zero downtime)
squid -k reconfigure
```

## New Relic Integration (Logs & Metrics)

To send Squid access logs and cache metrics to New Relic, enable it during the `install.sh` prompts or set the Ansible variable:

```yaml
# group_vars/all.yml or extra-vars
nr_integration_enabled: true
```

Requires the NR Infrastructure Agent to be installed on the same host. The script automatically deploys:

1. Log forwarding configuration (`/etc/newrelic-infra/logging.d/squid.yml`)
2. Metrik Flex integration (`/etc/newrelic-infra/integrations.d/squid-metrics.yml`)

## Uninstall

```bash
# Standalone script
sudo bash uninstall.sh

# Or via Ansible
ansible-playbook teardown.yml
```

## Diagnostic Support Bundle

If you encounter connection issues, generate a diagnostic archive:

```bash
sudo bash support-bundle.sh
```

This generates a `.tar.gz` file in `/tmp/` containing:

- System info (OS, uptime, disk, memory)
- Squid version and compile flags
- Squid configuration (passwords automatically masked)
- Last 1000 lines of access.log and cache.log
- Port, firewall, and SELinux status
- Connectivity test results to New Relic

## Project Structure

```text
├── install.sh                  # Bootstrap installer (interactive)
├── uninstall.sh                # Standalone uninstaller
├── support-bundle.sh           # Diagnostic archive generator
├── ansible.cfg                 # Ansible configuration
├── inventory/localhost.ini     # Localhost inventory
├── site.yml                    # Main installation playbook
├── verify.yml                  # Verification playbook
├── teardown.yml                # Uninstall playbook (Ansible)
├── roles/
│   ├── squid_proxy/            # Squid installation & configuration role
│   │   ├── defaults/main.yml   # Default variables
│   │   ├── vars/               # OS-specific variables
│   │   ├── tasks/              # Installation & configuration tasks
│   │   ├── handlers/           # Service restart & reconfigure handlers
│   │   └── templates/          # squid.conf.j2, allowed_domains.txt.j2, nr-logging.yml.j2
│   └── verify/                 # Endpoint verification role
├── legacy/                     # Legacy configuration files (reference)
└── legacy/docs/                # Project roadmap and planning docs (original Indonesian)
```

## Re-run Playbook Manually

```bash
cd /opt/newrelic-squid-proxy

# Install/reconfigure
ansible-playbook site.yml --extra-vars '{"squid_port": 3128, "ssl_bump_enabled": false, "basic_auth_enabled": false}'

# Verify
ansible-playbook verify.yml --extra-vars '{"squid_port": 3128, "ssl_bump_enabled": false, "basic_auth_enabled": false}'
```

## Troubleshooting

- **Port already in use**: Use a different port when prompted, or check `ss -tlnp | grep :3128`
- **Firewall blocking**: Ensure the proxy port is open in your firewall (`ufw allow 3128` or `firewall-cmd --add-port=3128/tcp --permanent`)
- **Domain blocked**: Edit `/etc/squid/allowed_domains.txt`, then run `squid -k reconfigure`
- **Squid fails to start**: Check configuration (`squid -k parse`) and logs (`tail -f /var/log/squid/cache.log`)
- **SELinux blocking**: Check `audit2why < /var/log/audit/audit.log` or run with `squid_selinux_enabled: true`
- **Need full diagnostics**: Run `sudo bash support-bundle.sh` and send the `.tar.gz` to New Relic Support

## Requirements

- Linux (Ubuntu, Debian, CentOS, RHEL, Rocky, Alma, Fedora, SLES, openSUSE)
- Root or sudo access
- curl or wget (for download)
- Internet access (to download Ansible and Squid)

## License

MIT License - see [LICENSE](LICENSE)
