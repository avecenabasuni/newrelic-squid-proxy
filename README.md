# New Relic Squid Proxy

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Ansible](https://img.shields.io/badge/Ansible-2.14+-black.svg?style=flat&logo=ansible)](https://www.ansible.com/)
[![OS: Linux](https://img.shields.io/badge/OS-Linux-orange.svg?style=flat&logo=linux)](https://www.linux.org/)

Automated installation and configuration of **Squid Proxy** to support New Relic POCs in environments requiring a forward proxy.



## 💡 Motivation & Problem Statement

Conducting a Proof of Concept (POC) for New Relic in strict enterprise environments often requires a **forward proxy** to allow agents to reach ingest endpoints. 

Manually setting up Squid Proxy is a repetitive and error-prone process involving:
- Manual package installation and service management.
- Complex configuration of SSL Bump (MITM) for TLS inspection.
- Precise domain whitelisting for 30+ New Relic endpoints.
- Vulnerability to configuration drift and lack of idempotency.

**This project automates the entire lifecycle**—from OS detection to final endpoint verification—reducing a 30-minute manual task to a **one-liner command**.

### 🚀 Efficiency Gain (Manual vs. Automated)

| Feature | Manual Process | **Automated (This Repo)** |
| :--- | :--- | :--- |
| **Duration** | ~30 Minutes | **< 2 Minutes** |
| **Consistency** | Human Error Prone | **100% Idempotent** |
| **SSL Bump** | High Complexity | **Full Auto-Generation** |
| **Verification** | Manual `curl` Tests | **Automated 32+ Checks** |



## ✨ Features

- **One-liner install** - `curl -sSL <URL>/install.sh | sudo bash`
- **Multi-distro Support** - Ubuntu, Debian, CentOS, RHEL, Rocky, Alma, Fedora, SLES, openSUSE.
- **SSL Bump (optional)** - Automated MITM interception for TLS traffic to New Relic.
- **Basic Auth (optional)** - Secure proxy access via htpasswd.
- **Cache Peer (optional)** - Corporate proxy chaining for complex networks.
- **Dynamic ACLs** - Manage allowed domains without service restarts.
- **Log Forwarding** - Integrated Squid monitoring via New Relic Infrastructure Agent.
- **SELinux Aware** - Auto-configures contexts on RHEL-based systems.
- **Verification Engine** - Built-in connectivity tests for all target endpoints.



## 🛠️ Quick Start

### Automated Installation (Recommended)

```bash
curl -sSL https://raw.githubusercontent.com/avecenabasuni/newrelic-squid-proxy/main/install.sh | sudo bash
```

The script will automatically:
1. Detect OS and package manager.
2. Install Ansible (`ansible-core >= 2.14`) if not present.
3. Display interactive configuration prompts.
4. Install and configure Squid Proxy idempotently.
5. Run connection verification to all New Relic endpoints.

### Manual Installation

```bash
# Clone repository
git clone https://github.com/avecenabasuni/newrelic-squid-proxy.git
cd newrelic-squid-proxy

# Run installer
sudo bash install.sh
```



## ⚙️ Configuration

All configuration is handled via interactive prompts during installation:

| Parameter | Default | Description |
| --------- | ------- | ----------- |
| Proxy Port | `3128` | HTTP proxy port |
| NR Region | `us` | Select New Relic region (us/eu/both) for ACL filtering |
| SSL Bump | `disabled` | Enable MITM interception (auto-generate or use existing cert) |
| Basic Auth | `disabled` | Enable proxy authentication |
| Cache Peer | `disabled` | Chain to an upstream corporate proxy |
| NR Integration | `disabled` | Deploy Flex metrics & Log forwarding configs |



## 📈 Dashboarding

If **NR Integration** is enabled, you can import the provided `dashboard.json` into your New Relic account to monitor:
- Total HTTP Requests (Client vs. Server)
- Cache Hit Ratio
- Active Connections
- Peak Memory Usage
- Forwarded Access Logs



## 🧹 Housekeeping & Support

### Uninstall

```bash
sudo bash uninstall.sh
```

### Diagnostic Bundle

If you encounter issues, generate a support archive for troubleshooting:

```bash
sudo bash support-bundle.sh
```



## 📁 Project Structure

```text
├── install.sh                  # Bootstrap installer (interactive)
├── uninstall.sh                # Standalone uninstaller
├── dashboard.json              # New Relic OOTB Dashboard
├── site.yml                    # Main installation playbook
├── verify.yml                  # Verification playbook
├── roles/
│   ├── squid_proxy/            # Core installation & configuration
│   └── verify/                 # Connectivity testing logic
├── legacy/                     # Archived configuration files
└── legacy/docs/                # Project design & roadmap documents
```



## 📜 License

This project is licensed under the **MIT License** - see the [LICENSE](LICENSE) file for details.


*Created by **Avecena Basuni** to simplify New Relic observability adoption.*
