# Puppet + Windows: Complete Installation, Setup and Configuration Guide

> **Audience:** System administrators and engineers who have completed the Puppet Base Course (Days 1–3) and want a thorough operational reference for running Puppet in a mixed Linux/Windows environment.
>
> **Scope:** Covers every step from a blank Puppet Server and a fresh Windows node through to a fully managed, production-ready Windows estate — including troubleshooting, security hardening, Chocolatey, the DSC bridge, and Puppet Bolt.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Prerequisites and System Requirements](#2-prerequisites-and-system-requirements)
3. [Network and Firewall Requirements](#3-network-and-firewall-requirements)
4. [Puppet Server Setup (Linux)](#4-puppet-server-setup-linux)
5. [Preparing the Windows Node](#5-preparing-the-windows-node)
6. [Installing the Puppet Agent on Windows](#6-installing-the-puppet-agent-on-windows)
7. [Agent Configuration (`puppet.conf`)](#7-agent-configuration-puppetconf)
8. [Certificate Lifecycle Management](#8-certificate-lifecycle-management)
9. [Triggering and Verifying Runs](#9-triggering-and-verifying-runs)
10. [The Windows Directory Layout](#10-the-windows-directory-layout)
11. [Installing Core Windows Modules](#11-installing-core-windows-modules)
12. [Chocolatey Package Management](#12-chocolatey-package-management)
13. [Managing Files and NTFS Permissions](#13-managing-files-and-ntfs-permissions)
14. [Managing the Windows Registry](#14-managing-the-windows-registry)
15. [Managing Services and the SCM](#15-managing-services-and-the-scm)
16. [Managing Local Users and Groups](#16-managing-local-users-and-groups)
17. [Environment Variables](#17-environment-variables)
18. [Running PowerShell from Puppet](#18-running-powershell-from-puppet)
19. [IIS Management](#19-iis-management)
20. [DSC (Desired State Configuration) Integration](#20-dsc-desired-state-configuration-integration)
21. [Windows Facts and Conditional Manifests](#21-windows-facts-and-conditional-manifests)
22. [Cross-Platform Module Design](#22-cross-platform-module-design)
23. [Hiera Data for Windows](#23-hiera-data-for-windows)
24. [Puppet Bolt on Windows](#24-puppet-bolt-on-windows)
25. [Autosigning for Windows Nodes](#25-autosigning-for-windows-nodes)
26. [Running the Agent as a Non-SYSTEM Account](#26-running-the-agent-as-a-non-system-account)
27. [Security Hardening Reference](#27-security-hardening-reference)
28. [Troubleshooting](#28-troubleshooting)
29. [Quick Reference Cheat Sheet](#29-quick-reference-cheat-sheet)

---

## 1. Architecture Overview

The Puppet architecture is identical for Windows and Linux. The Puppet Server (which always runs on Linux) compiles catalogs for all nodes regardless of operating system. The `puppet-agent` MSI on Windows contains a full, self-contained Ruby runtime so there are no operating system dependencies.

```
┌──────────────────────────────────────────────────────────────────┐
│                        Puppet Server (Linux)                     │
│                                                                  │
│   ┌───────────────┐  ┌──────────────┐  ┌──────────────────────┐ │
│   │ Catalog       │  │ Certificate  │  │   Hiera / Data       │ │
│   │ Compiler      │  │ Authority    │  │   Lookup             │ │
│   │ (JRuby)       │  │ (puppetCA)   │  │                      │ │
│   └───────────────┘  └──────────────┘  └──────────────────────┘ │
│           │                                                      │
│   Port 8140 (HTTPS + TLS client certificate authentication)      │
└───────────┼──────────────────────────────────────────────────────┘
            │
    ┌───────┴─────────────────────────────────────────────────┐
    │                                                         │
    ▼                                                         ▼
┌────────────────────────┐                 ┌────────────────────────┐
│   Linux Agent          │                 │   Windows Agent        │
│   puppet-agent         │                 │   puppet-agent MSI     │
│   /opt/puppetlabs/     │                 │   C:\Program Files\    │
│                        │                 │   Puppet Labs\Puppet\  │
│   Providers:           │                 │                        │
│   apt, yum, dnf        │                 │   Providers:           │
│   posix users/groups   │                 │   chocolatey, windows  │
│   systemd services     │                 │   windows users/groups │
│   file (POSIX perms)   │                 │   SCM services         │
│                        │                 │   file (NTFS ACLs)     │
└────────────────────────┘                 │   registry_key/value   │
                                           │   PowerShell bridge    │
                                           │   DSC bridge (LCM)     │
                                           └────────────────────────┘
```

**Key principle:** The Puppet language, Hiera, modules, and r10k work identically. Only the *providers* differ — they are the platform-specific implementation detail hidden below the resource abstraction layer.

---

## 2. Prerequisites and System Requirements

### Puppet Server

| Component | Minimum | Recommended (production) |
|---|---|---|
| OS | Ubuntu 20.04 / Rocky Linux 8 | Ubuntu 22.04 / Rocky Linux 9 |
| CPU | 2 cores | 4+ cores |
| RAM | 4 GB | 8 GB (for 100+ agents) |
| Disk | 20 GB | 100 GB SSD (for PuppetDB + reports) |
| Java | Bundled (OpenJDK 11) | — |
| Hostname | Resolvable FQDN | `puppet.example.com` |

> The Puppet Server is **not supported on Windows**. It must run on a Linux system.

### Windows Agent Node

| Component | Minimum | Notes |
|---|---|---|
| OS | Windows Server 2012 R2 / Windows 8.1 | Puppet 8 requires Windows Server 2016+ or Windows 10+ |
| CPU | 1 core | — |
| RAM | 512 MB | 1 GB+ recommended |
| Disk | 500 MB free | For agent installation + catalog cache |
| PowerShell | 3.0+ | 5.1 required for DSC integration |
| .NET Framework | 4.0+ | Required for some MSI installations |
| Architecture | x86\_64 (64-bit) | 32-bit not supported by Puppet 8 |

### Puppet 8 — Supported Windows Versions

| Windows Version | Supported |
|---|---|
| Windows Server 2022 | ✓ Yes |
| Windows Server 2019 | ✓ Yes |
| Windows Server 2016 | ✓ Yes |
| Windows 11 | ✓ Yes |
| Windows 10 (1903+) | ✓ Yes |
| Windows Server 2012 R2 | ✗ No (Puppet 8 dropped support) |
| Windows Server 2008 R2 | ✗ No |

> For legacy Windows (2012 R2 and older), use **Puppet 7.x** (supported until November 2027).

---

## 3. Network and Firewall Requirements

All communication is initiated by the **agent** to the **server**. The server never connects to agents.

| Source | Destination | Port | Protocol | Purpose |
|---|---|---|---|---|
| Windows agent | Puppet Server | **8140** | TCP (HTTPS) | Catalog requests, file serving, certificate requests |
| Windows agent | PuppetDB (optional) | 8081 | TCP (HTTPS) | Report submission (if PuppetDB is on a separate host) |
| Puppet Server | PuppetDB | 8081 | TCP (HTTPS) | Catalog storage, fact storage |
| Admin workstation | Puppet Server | 8140 | TCP | `puppetserver ca` commands |

### Configuring the Windows Firewall

By default, Windows Firewall allows all outbound connections, so no outbound rule is needed for port 8140. If your organization's policy restricts outbound traffic:

```powershell
# Allow outbound TCP 8140 to the Puppet Server
New-NetFirewallRule `
  -DisplayName   "Puppet Agent — Puppet Server (outbound)" `
  -Direction     Outbound `
  -Protocol      TCP `
  -RemoteAddress 192.168.1.10 `
  -RemotePort    8140 `
  -Action        Allow
```

### Configuring the Linux Firewall (Puppet Server side)

```bash
# Ubuntu (ufw)
sudo ufw allow 8140/tcp
sudo ufw reload

# Rocky Linux / RHEL (firewalld)
sudo firewall-cmd --permanent --add-port=8140/tcp
sudo firewall-cmd --reload

# Verify the port is open and listening
sudo ss -tlnp | grep 8140
```

---

## 4. Puppet Server Setup (Linux)

> If you already have a working Puppet Server from the Day 1 exercises, skip to Section 5. This section is the full reference for setting one up from scratch.

### 4.1 Configure the Puppet Platform Repository

**Ubuntu 22.04:**
```bash
wget https://apt.puppet.com/puppet8-release-jammy.deb
sudo dpkg -i puppet8-release-jammy.deb
sudo apt-get update
```

**Rocky Linux 9 / RHEL 9:**
```bash
sudo rpm -Uvh https://yum.puppet.com/puppet8-release-el-9.noarch.rpm
sudo dnf makecache
```

### 4.2 Install and Configure `puppetserver`

```bash
# Ubuntu
sudo apt-get install -y puppetserver

# Rocky / RHEL
sudo dnf install -y puppetserver
```

Set the server hostname in `puppet.conf`:

```bash
sudo puppet config set server puppet.example.com --section main
sudo puppet config set certname puppet.example.com --section main
```

Edit JVM memory allocation (file location varies by OS):

```bash
# Ubuntu: /etc/default/puppetserver
# Rocky:  /etc/sysconfig/puppetserver
JAVA_ARGS="-Xms2g -Xmx2g -Djruby.logger.class=com.puppetlabs.jruby_utils.jruby.Slf4jLogger"
```

Guidelines:
- Up to 20 agents → 2 GB
- 20–100 agents → 4 GB
- 100–400 agents → 8 GB
- 400+ agents → 12+ GB (consider multiple compile masters)

### 4.3 Start Puppet Server

```bash
sudo systemctl start puppetserver
sudo systemctl enable puppetserver

# Verify it started correctly
sudo systemctl status puppetserver
sudo journalctl -u puppetserver -n 50
sudo ss -tlnp | grep 8140
```

### 4.4 Set Up the Control Repository (recommended)

Install r10k for environment management:

```bash
sudo /opt/puppetlabs/puppet/bin/gem install r10k

# Create r10k config
sudo mkdir /etc/puppetlabs/r10k
cat <<'EOF' | sudo tee /etc/puppetlabs/r10k/r10k.yaml
---
cachedir: /opt/puppetlabs/puppet/cache/r10k
sources:
  puppet:
    remote: 'git@github.com:myorg/puppet-control.git'
    basedir: /etc/puppetlabs/code/environments
EOF

# Deploy the production environment
sudo r10k deploy environment production -p
```

---

## 5. Preparing the Windows Node

### 5.1 Set the Hostname

The hostname becomes the Puppet certificate name. Set it correctly **before** installing the agent — changing it later requires revoking and re-issuing the certificate.

```powershell
# Set the computer name
Rename-Computer -NewName "win01" -Restart
# After reboot, verify
$env:COMPUTERNAME
```

> **Best practice:** Use a naming convention that reflects role and environment, e.g. `web01-prod`, `db01-test`. The certificate name (`certname`) should be the FQDN: `win01.example.com`.

### 5.2 Configure DNS or `/etc/hosts`

The Windows node must resolve `puppet.example.com` (or whatever your server hostname is):

```powershell
# Option A — Add to hosts file (lab/testing)
$puppetIp   = '192.168.1.10'
$hostsFile  = 'C:\Windows\System32\drivers\etc\hosts'
$hostsEntry = "$puppetIp  puppet.example.com  puppet"

$existing = Select-String -Path $hostsFile -Pattern 'puppet\.example\.com' -Quiet
if (-not $existing) {
    Add-Content -Path $hostsFile -Value $hostsEntry -Encoding ASCII
    Write-Host "Added: $hostsEntry"
} else {
    Write-Host "Entry already present."
}
```

```powershell
# Option B — DNS (production) — configure on your DNS server
# Verify resolution
Resolve-DnsName puppet.example.com
[System.Net.Dns]::GetHostEntry('puppet.example.com')
```

### 5.3 Verify Connectivity to the Puppet Server

```powershell
# Network reachability
Test-NetConnection -ComputerName puppet.example.com -Port 8140 -InformationLevel Detailed

# Output should include: TcpTestSucceeded : True
```

### 5.4 Set PowerShell Execution Policy

The Puppet agent uses PowerShell internally. Ensure it can run scripts:

```powershell
# Check current policy
Get-ExecutionPolicy -List

# Set RemoteSigned for the system (allows locally-created scripts + signed remote scripts)
Set-ExecutionPolicy RemoteSigned -Scope LocalMachine -Force

# Verify
Get-ExecutionPolicy -Scope LocalMachine
```

### 5.5 Ensure WinRM Is Accessible (Required for Puppet Bolt / Ad-Hoc Tasks)

WinRM is only needed for Puppet Bolt and PE Tasks — the regular agent uses HTTPS/8140 not WinRM. If you plan to use Bolt:

```powershell
# Enable WinRM with HTTPS
winrm quickconfig -quiet

# For Bolt with HTTPS, configure a listener (see Section 24)
```

---

## 6. Installing the Puppet Agent on Windows

### 6.1 Method 1 — Interactive MSI Wizard

1. Download from: `https://downloads.puppet.com/windows/puppet8/puppet-agent-x64-latest.msi`
2. Run the MSI. The wizard asks for:
   - **Puppet Master** (server hostname, default: `puppet`)
   - **Agent certname** (default: system FQDN)
   - **Environment** (default: `production`)
3. The MSI configures `puppet.conf`, creates the service, and adds Puppet binaries to `PATH`.

### 6.2 Method 2 — Silent MSI (Recommended)

```powershell
# Download
$msiUrl  = 'https://downloads.puppet.com/windows/puppet8/puppet-agent-x64-latest.msi'
$msiPath = "$env:TEMP\puppet-agent.msi"
Invoke-WebRequest -Uri $msiUrl -OutFile $msiPath -UseBasicParsing

# Install silently
$msiArgs = @(
    '/qn', '/norestart',
    "/l*v $env:TEMP\puppet-install.log",
    '/i', $msiPath,
    'PUPPET_SERVER=puppet.example.com',
    "PUPPET_AGENT_CERTNAME=$($env:COMPUTERNAME.ToLower()).example.com",
    'PUPPET_AGENT_ENVIRONMENT=production',
    'PUPPET_AGENT_STARTUP_MODE=Manual'
)
$result = Start-Process msiexec -ArgumentList $msiArgs -Wait -PassThru -NoNewWindow
Write-Host "Exit code: $($result.ExitCode)"
# 0 = success, 3010 = success but reboot required, anything else = error
```

**All MSI properties:**

| Property | Default | Description |
|---|---|---|
| `PUPPET_SERVER` | `puppet` | Puppet Server hostname or IP |
| `PUPPET_MASTER_PORT` | `8140` | Puppet Server port |
| `PUPPET_AGENT_CERTNAME` | system FQDN (lowercase) | Certificate name — must be unique |
| `PUPPET_AGENT_ENVIRONMENT` | `production` | Puppet environment |
| `PUPPET_AGENT_STARTUP_MODE` | `Automatic` | Windows service startup: `Automatic`, `Manual`, `Disabled` |
| `PUPPET_AGENT_ACCOUNT_USER` | — | Service account username |
| `PUPPET_AGENT_ACCOUNT_PASSWORD` | — | Service account password |
| `PUPPET_AGENT_ACCOUNT_DOMAIN` | `.` (local) | Service account domain |
| `REINSTALLMODE` | — | MSI reinstall flags (set to `amus` for clean upgrade) |

### 6.3 Method 3 — Bootstrap via a Script (for mass deployment)

Use this pattern to deploy the agent to many nodes from a central location:

```powershell
# bootstrap-puppet.ps1
# Run this remotely via WinRM, SCCM, Intune, or Group Policy

param(
    [string]$PuppetServer      = 'puppet.example.com',
    [string]$Environment       = 'production',
    [string]$PuppetVersion     = 'latest',
    [string]$MsiDownloadServer = 'https://downloads.puppet.com'
)

$ErrorActionPreference = 'Stop'

# Check if already installed
$puppetSvc = Get-Service -Name puppet -ErrorAction SilentlyContinue
if ($puppetSvc) {
    Write-Host "Puppet agent already installed — version: $(puppet --version)"
    exit 0
}

# Determine the download URL
if ($PuppetVersion -eq 'latest') {
    $msiUrl = "$MsiDownloadServer/windows/puppet8/puppet-agent-x64-latest.msi"
} else {
    $msiUrl = "$MsiDownloadServer/windows/puppet8/puppet-agent-$PuppetVersion-x64.msi"
}

$msiPath = "$env:TEMP\puppet-agent.msi"
$logPath = "$env:TEMP\puppet-agent-install.log"
$certName = "$($env:COMPUTERNAME.ToLower()).example.com"

Write-Host "Downloading from $msiUrl ..."
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri $msiUrl -OutFile $msiPath -UseBasicParsing

Write-Host "Installing puppet-agent for certname=$certName ..."
$msiArgs = "/qn /norestart /l*v `"$logPath`" /i `"$msiPath`" " +
           "PUPPET_SERVER=$PuppetServer " +
           "PUPPET_AGENT_CERTNAME=$certName " +
           "PUPPET_AGENT_ENVIRONMENT=$Environment " +
           "PUPPET_AGENT_STARTUP_MODE=Manual"

$proc = Start-Process msiexec -ArgumentList $msiArgs -Wait -PassThru -NoNewWindow
if ($proc.ExitCode -notin @(0, 3010)) {
    throw "MSI install failed (exit $($proc.ExitCode)). See $logPath"
}

Write-Host "Puppet agent installed. Triggering first run to submit CSR ..."
& "C:\Program Files\Puppet Labs\Puppet\bin\puppet.bat" agent --test --waitforcert 0
Write-Host "CSR submitted. Sign the certificate on the Puppet Server:"
Write-Host "  puppetserver ca sign --certname $certName"
```

### 6.4 Method 4 — Chocolatey (if Chocolatey is already present)

```powershell
# If Chocolatey is already bootstrapped on the image
choco install puppet-agent --yes `
  --params "'/Server:puppet.example.com /Certname:win01.example.com'"
```

### 6.5 Method 5 — Group Policy / SCCM / Intune

Wrap the silent MSI command (Method 2) in a `.cmd` wrapper for Group Policy Software Installation, or upload the MSI as a Win32 App in Intune with these detection rules:

- **Detection:** Registry key `HKLM\SOFTWARE\Puppet Labs\Puppet` exists
- **Install command:** `msiexec /qn /i puppet-agent.msi PUPPET_SERVER=puppet.example.com ...`
- **Uninstall command:** `msiexec /qn /x puppet-agent.msi`

---

## 7. Agent Configuration (`puppet.conf`)

Location: `C:\ProgramData\PuppetLabs\puppet\etc\puppet.conf`

### 7.1 Full Reference Configuration

```ini
# puppet.conf — Windows agent
# Location: C:\ProgramData\PuppetLabs\puppet\etc\puppet.conf

[main]
# ── Identity ──────────────────────────────────────────────────────────────────
# certname: the node's unique identity in Puppet — MUST match the certificate CN
# Use the FQDN. Once set and the cert is signed, changing this requires
# revoking the old cert on the server.
certname    = win01.example.com

# server: hostname of the Puppet Server (must resolve from this node)
# For Puppet Enterprise or multi-server setups, this is the primary server.
server      = puppet.example.com

# environment: the Puppet environment to request catalogs from
# Change per node or via Hiera node data
environment = production

# ── Certificate ───────────────────────────────────────────────────────────────
# ca_server: CA hostname (same as server by default)
# Only set this if you have a dedicated CA server
# ca_server = ca.example.com

# ── Logging ───────────────────────────────────────────────────────────────────
# logdest: where to write the agent log
# On Windows this is the Windows Event Log by default; set 'console' for output
# logdest = C:/ProgramData/PuppetLabs/puppet/cache/log/puppet.log

[agent]
# ── Run interval ──────────────────────────────────────────────────────────────
# runinterval: seconds between automatic catalog runs (default: 1800 = 30 min)
runinterval = 1800

# ── Certificate wait ──────────────────────────────────────────────────────────
# waitforcert: how many seconds to wait for the certificate to be signed
# on the server before giving up (0 = do not wait)
waitforcert = 120

# ── Reporting ─────────────────────────────────────────────────────────────────
# report: send run reports to PuppetDB (requires PuppetDB to be configured)
report = true

# ── Noop mode ─────────────────────────────────────────────────────────────────
# noop: if true, all runs are dry-runs — no changes are applied
# noop = false

# ── Splaylimit ────────────────────────────────────────────────────────────────
# splaylimit: randomise the first run time to prevent thundering herd
# when many agents start simultaneously (e.g. after a mass reboot)
# splaylimit = 1800

# ── Usecacheonfailure ─────────────────────────────────────────────────────────
# usecacheonfailure: if the server is unreachable, apply the last cached catalog
# usecacheonfailure = true

# ── Graph ────────────────────────────────────────────────────────────────────
# graph: output a DOT file of the dependency graph after each run (debugging)
# graph = false
```

### 7.2 Verifying Configuration

```powershell
# Print all effective settings (includes defaults)
puppet config print

# Print a specific setting
puppet config print server
puppet config print certname
puppet config print runinterval
puppet config print environment

# Show which config file a setting comes from
puppet config print server --section main
```

### 7.3 Changing the Environment per Node

Use Hiera or `puppet.conf` to change environment:

```powershell
# Set this node to the 'staging' environment
puppet config set environment staging --section agent
```

Or set it via the node classifier (Enterprise) or in `site.pp` if using ENC.

---

## 8. Certificate Lifecycle Management

Puppet uses **mutual TLS** — both server and agent authenticate with certificates signed by the Puppet CA.

### 8.1 The Full Certificate Flow

```
Windows Agent                          Puppet Server
─────────────────────────────────────────────────────
1. puppet agent --test
   │
   ├─ Generates private key (win01.pem)
   ├─ Creates CSR (Certificate Signing Request)
   └──────────── Sends CSR ─────────────────────────→

                                       2. CSR stored in
                                          puppet-ca/requests/

                                       3. Admin runs:
                                          puppetserver ca sign
                                          --certname win01.example.com
                                          └─ CA signs the cert

4. puppet agent --test (retry)
   │
   └──────────── Requests signed cert ──────────────→
                                       └─ Returns signed cert

5. Agent stores cert:
   ssl/certs/win01.example.com.pem

6. All future catalog requests use
   client certificate for authentication
```

### 8.2 Listing and Signing Certificates

```bash
# On the Puppet Server (Linux)

# List all pending (unsigned) requests
sudo puppetserver ca list

# List all signed certificates
sudo puppetserver ca list --all

# Sign a single node
sudo puppetserver ca sign --certname win01.example.com

# Sign all pending requests (use with care in production)
sudo puppetserver ca sign --all

# Revoke a certificate (e.g. node decommissioned or compromised)
sudo puppetserver ca revoke --certname win01.example.com

# Clean (revoke + delete) a certificate — allows re-bootstrapping
sudo puppetserver ca clean --certname win01.example.com
```

### 8.3 Re-Bootstrapping a Node (Certificate Reset)

If the certificate is corrupt, the node was reprovisioned, or `certname` was changed:

```powershell
# On the Windows node — delete all local SSL files
$sslDir = 'C:\ProgramData\PuppetLabs\puppet\etc\ssl'
Remove-Item -Path $sslDir -Recurse -Force
Write-Host "SSL directory cleared"
```

```bash
# On the Puppet Server — clean the old certificate
sudo puppetserver ca clean --certname win01.example.com
```

```powershell
# On the Windows node — re-submit the CSR
puppet agent --test
# New CSR will appear on the server — sign it again
```

### 8.4 Certificate Fingerprint Verification

When signing certificates, compare fingerprints to prevent MITM attacks:

```powershell
# On the Windows agent — print the fingerprint of the pending CSR
puppet ssl fingerprint
# Output: (SHA256) AB:CD:EF:...
```

```bash
# On the Puppet Server — compare before signing
sudo puppetserver ca list
# Output: win01.example.com  (SHA256) AB:CD:EF:...  ← must match
```

### 8.5 Certificate Expiry

By default, Puppet certificates expire after **5 years**. Plan for renewal:

```bash
# Check certificate expiry date on the server
sudo openssl x509 -in /etc/puppetlabs/puppet/ssl/certs/win01.example.com.pem \
  -noout -dates

# Puppet 7.12+ supports automatic certificate renewal
# puppet.conf on agent:
# [agent]
# certificate_revocation = chain
# renew_cert = true    # automatically request renewal 90 days before expiry
```

---

## 9. Triggering and Verifying Runs

### 9.1 Running the Agent

```powershell
# Interactive run — shows all output, applies changes
puppet agent --test

# Dry run (noop) — shows what WOULD change, applies nothing
puppet agent --test --noop

# Verbose output — includes debug-level messages
puppet agent --test --debug

# Run against a specific environment (overrides puppet.conf)
puppet agent --test --environment staging

# Run and exit with error code if changes were needed (useful in CI)
puppet agent --test; if ($LASTEXITCODE -gt 0) { exit $LASTEXITCODE }
```

### 9.2 Understanding Exit Codes

| Exit Code | Meaning |
|---|---|
| `0` | Success — no changes, catalog applied cleanly |
| `1` | Error — catalog compilation or application failed |
| `2` | Success with changes — at least one resource was changed |
| `4` | Failure — at least one resource failed |
| `6` | Changes + failures — some resources changed, some failed |

```powershell
puppet agent --test
Write-Host "Exit code: $LASTEXITCODE"

# Use in scripts:
if ($LASTEXITCODE -eq 1 -or $LASTEXITCODE -eq 4 -or $LASTEXITCODE -eq 6) {
    Write-Error "Puppet run had errors"
    exit 1
}
```

### 9.3 The Agent Service

```powershell
# Start the agent service
Start-Service puppet

# Stop the agent service
Stop-Service puppet

# Set startup type
Set-Service puppet -StartupType Automatic     # start on boot
Set-Service puppet -StartupType Manual        # manual only
Set-Service puppet -StartupType Disabled      # prevent starting

# Check status
Get-Service puppet | Select-Object Name, Status, StartType

# Restart the service (e.g. after changing puppet.conf)
Restart-Service puppet
```

### 9.4 Viewing Run Reports

```powershell
# Summary of the last run
$summary = Get-Content 'C:\ProgramData\PuppetLabs\puppet\cache\state\last_run_summary.yaml' -Raw
$summary

# Find errors in recent logs (Windows Event Log)
Get-WinEvent -LogName Application -MaxEvents 100 |
    Where-Object { $_.ProviderName -like '*puppet*' -and $_.LevelDisplayName -in @('Error','Warning') }

# Puppet logs to the Application event log under "Puppet" source
Get-EventLog -LogName Application -Source 'Puppet' -Newest 20
```

### 9.5 Checking Which Resources Were Changed

```powershell
# Run with --summarize for a compact change summary
puppet agent --test --summarize

# Parse the YAML summary file programmatically
$yaml  = Get-Content 'C:\ProgramData\PuppetLabs\puppet\cache\state\last_run_summary.yaml' -Raw
# Key fields: resources.changed, resources.failed, resources.total
```

---

## 10. The Windows Directory Layout

Understanding where Puppet puts things on Windows is essential for troubleshooting.

```
C:\Program Files\Puppet Labs\Puppet\       ← Installation directory (read-only at runtime)
├── bin\
│   ├── puppet.bat           ← wrapper that calls the Ruby puppet binary
│   ├── facter.bat           ← fact collection wrapper
│   ├── hiera.bat            ← Hiera lookup wrapper
│   └── ruby.bat             ← access to the bundled Ruby runtime
├── puppet\                  ← Puppet core Ruby library
├── facter\                  ← Facter Ruby library
└── sys\
    └── ruby\                ← Bundled Ruby runtime (completely isolated)
        ├── bin\ruby.exe
        └── lib\

C:\ProgramData\PuppetLabs\                 ← Runtime data (writable)
├── puppet\
│   ├── etc\
│   │   ├── puppet.conf      ← Main configuration file  ← YOU EDIT THIS
│   │   ├── hiera.yaml       ← Local Hiera config (overrides server)
│   │   ├── csr_attributes.yaml ← Extra attributes to embed in the CSR
│   │   └── ssl\
│   │       ├── ca\
│   │       │   └── ca.pem   ← Puppet CA certificate
│   │       ├── certs\
│   │       │   └── win01.example.com.pem  ← Signed agent certificate
│   │       ├── certificate_requests\
│   │       │   └── win01.example.com.pem  ← Pending CSR (before signing)
│   │       └── private_keys\
│   │           └── win01.example.com.pem  ← Agent private key (PROTECT THIS)
│   └── cache\
│       ├── catalog\
│       │   └── win01.example.com.json     ← Last successfully applied catalog
│       ├── state\
│       │   ├── last_run_summary.yaml      ← Run statistics
│       │   ├── last_run_report.yaml       ← Full last run report
│       │   └── state.yaml                 ← Resource state tracking
│       ├── log\
│       │   └── puppet.log                 ← Agent log file
│       └── lib\
│           └── puppet\                    ← Plugin files synced from server (facts, types, providers)
└── facter\
    └── facts.d\             ← External facts directory (YOUR CUSTOM FACTS GO HERE)
        ├── my_fact.txt      ← key=value facts
        ├── my_fact.json     ← structured JSON facts
        └── my_fact.ps1      ← PowerShell facts
```

---

## 11. Installing Core Windows Modules

Run all module installations on the **Puppet Server**.

### 11.1 Essential Windows Modules

```bash
# Package management
sudo puppet module install puppetlabs-chocolatey     # Chocolatey integration
sudo puppet module install puppetlabs-powershell     # PowerShell exec provider

# File and permission management
sudo puppet module install puppetlabs-acl            # NTFS ACL management

# Registry management
sudo puppet module install puppetlabs-registry       # Registry key/value management

# Environment variables
sudo puppet module install puppet-windows_env        # System/user env vars

# IIS
sudo puppet module install puppetlabs-iis            # IIS sites, pools, bindings

# Windows features
sudo puppet module install puppet-windowsfeature     # Windows Server roles/features

# DSC bridge
sudo puppet module install puppet-dsc_lite           # Generic DSC resource bridge

# stdlib (almost always required)
sudo puppet module install puppetlabs-stdlib
```

### 11.2 Using a Puppetfile (Recommended)

Add to your control repository's `Puppetfile`:

```ruby
# Puppetfile

# Core
mod 'puppetlabs-stdlib',        '9.6.0'

# Windows
mod 'puppetlabs-chocolatey',    '7.0.0'
mod 'puppetlabs-powershell',    '6.0.0'
mod 'puppetlabs-acl',           '4.0.0'
mod 'puppetlabs-registry',      '3.2.0'
mod 'puppet-windows_env',       '4.0.0'
mod 'puppetlabs-iis',           '9.0.2'
mod 'puppet-windowsfeature',    '3.0.1'
mod 'puppet-dsc_lite',          '1.4.0'
```

Deploy with r10k:

```bash
sudo r10k deploy environment production -p
```

### 11.3 Verify Module Installation

```bash
puppet module list
# Should list all installed modules with their versions

# Check module can be found on the modulepath
puppet config print modulepath
```

---

## 12. Chocolatey Package Management

Chocolatey is the standard package manager for Windows and the recommended approach for software management with Puppet.

### 12.1 Bootstrap Chocolatey via Puppet

```puppet
# In a profile or role class
class profile::windows::base {
  # Bootstrap Chocolatey — idempotent, safe to run every time
  class { 'chocolatey':
    chocolatey_download_url => 'https://chocolatey.org/install.ps1',
    log_output              => true,
    use_7zip                => false,
  }
}
```

> **Air-gapped environments:** Mirror the install script internally and set `chocolatey_download_url` to your internal URL.

### 12.2 Installing Packages

```puppet
# Install latest version
package { 'googlechrome':
  ensure   => installed,
  provider => chocolatey,
}

# Pin to a specific version
package { 'git':
  ensure   => '2.43.0',
  provider => chocolatey,
}

# Always upgrade to latest
package { 'vlc':
  ensure   => latest,
  provider => chocolatey,
}

# Install from a custom source
package { 'myapp':
  ensure          => '3.1.0',
  provider        => chocolatey,
  source          => 'https://nexus.example.com/repository/chocolatey',
  install_options => ['--params', '"/InstallDir:C:\\MyApp"'],
}

# Remove a package
package { 'telnet':
  ensure   => absent,
  provider => chocolatey,
}
```

### 12.3 Managing Chocolatey Sources

```puppet
# Add a corporate Nexus/Artifactory mirror
chocolateysource { 'corporate':
  ensure   => present,
  location => 'https://nexus.example.com/repository/chocolatey/',
  priority => 1,           # lower number = higher priority
  user     => 'choco_ro',
  password => Sensitive(lookup('chocolatey::source_password')),
  require  => Class['chocolatey'],
}

# Disable the public feed (air-gapped environments)
chocolateysource { 'chocolatey':
  ensure  => present,
  enabled => false,
  require => Class['chocolatey'],
}

# Add a local filesystem or UNC share source
chocolateysource { 'local':
  ensure   => present,
  location => '\\\\fileshare\chocolatey-packages',
  priority => 0,
  require  => Class['chocolatey'],
}
```

### 12.4 Chocolatey Features and Configuration

```puppet
# Require checksums (security)
chocolateyfeature { 'checksumFiles':
  ensure  => enabled,
  require => Class['chocolatey'],
}

# Set a proxy
chocolateyconfig { 'proxy':
  ensure  => present,
  value   => 'http://proxy.example.com:3128',
  require => Class['chocolatey'],
}

chocolateyconfig { 'proxyBypassList':
  ensure => present,
  value  => 'internal.example.com,*.corp.example.com',
}

# Set the cache location (keep packages on disk for reinstall without download)
chocolateyconfig { 'cacheLocation':
  ensure => present,
  value  => 'C:\ProgramData\chocolatey\cache',
}
```

### 12.5 Version Pinning with Hiera

```yaml
# data/roles/windows_developer.yaml
profile::windows::packages:
  git:
    version: '2.43.0'
  vscode:
    version: latest
  googlechrome:
    version: installed
  notepadplusplus:
    version: '8.6.0'
```

```puppet
# profile/manifests/windows.pp
class profile::windows {
  $packages = lookup('profile::windows::packages', Hash, hash, {})

  $packages.each |$name, $config| {
    package { $name:
      ensure   => $config['version'],
      provider => chocolatey,
      require  => Class['chocolatey'],
    }
  }
}
```

---

## 13. Managing Files and NTFS Permissions

### 13.1 Basic File Resource

```puppet
# Create a directory
file { 'C:/ProgramData/MyApp':
  ensure => directory,
}

# Manage a file with static content
file { 'C:/ProgramData/MyApp/version.txt':
  ensure  => file,
  content => "1.2.3\n",
  require => File['C:/ProgramData/MyApp'],
}

# Manage a file from a Puppet file server (modules/)
file { 'C:/ProgramData/MyApp/logo.png':
  ensure  => file,
  source  => 'puppet:///modules/myapp/logo.png',
  require => File['C:/ProgramData/MyApp'],
}

# Manage a directory tree recursively
file { 'C:/ProgramData/MyApp/conf.d':
  ensure  => directory,
  recurse => true,
  purge   => true,   # remove files not managed by Puppet
  source  => 'puppet:///modules/myapp/conf.d',
}

# Remove a file
file { 'C:/ProgramData/MyApp/old-config.ini':
  ensure => absent,
}
```

### 13.2 Path Format Rules

- **Always use forward slashes** — Puppet converts them: `C:/ProgramData/MyApp`
- **Or double backslashes** if you must: `C:\\ProgramData\\MyApp`
- UNC paths work: `//fileserver/share/file.txt`
- Long paths (> 260 chars) require Windows Long Path support (enable via registry/GPO)

### 13.3 NTFS ACLs with `puppetlabs-acl`

For simple ownership and mode use the built-in `file` resource. For production NTFS ACL management use `puppetlabs-acl`:

```puppet
# Full ACL management — break inheritance and set explicit entries
acl { 'C:/ProgramData/SecureApp':
  purge                      => true,    # remove all unmanaged ACEs
  inherit_parent_permissions => false,   # break permission inheritance
  permissions                => [
    {
      identity    => 'SYSTEM',
      rights      => ['full'],
      affects     => 'all',             # this object + all children
    },
    {
      identity    => 'Administrators',
      rights      => ['full'],
      affects     => 'all',
    },
    {
      identity    => 'svcMyApp',
      rights      => ['read', 'execute'],
      affects     => 'all',
      child_types => 'all',             # containers and objects
    },
    {
      identity    => 'Everyone',
      rights      => ['read'],
      type        => 'deny',            # deny entry
      affects     => 'self_only',
    },
  ],
}
```

**`affects` values:**
| Value | Applies to |
|---|---|
| `all` | This folder, sub-folders, and files |
| `self_only` | This folder only |
| `children_only` | Sub-folders and files only |
| `direct_children_only` | Direct children only (not nested) |
| `files_only` | Files in this folder and sub-folders |

**`rights` shortcuts:**
- `'full'` → FullControl
- `'modify'` → Modify
- `'write'` → Write
- `'read'` → ReadAndExecute
- `'execute'` → ReadAndExecute
- `['read','write']` → Custom combination

### 13.4 Line Endings and Encoding

```puppet
# CRLF in content string (explicit)
file { 'C:/MyApp/config.ini':
  ensure  => file,
  content => "[settings]\r\nkey=value\r\n",
}

# Use EPP template — the template's own line endings are preserved
file { 'C:/MyApp/config.ini':
  ensure  => file,
  content => epp('myapp/config.ini.epp', { key => 'value' }),
}
```

> For most Windows applications, **UTF-8 without BOM** and **LF** line endings work fine on modern Windows (10/Server 2016+). Only use CRLF when a specific legacy tool requires it.

---

## 14. Managing the Windows Registry

### 14.1 Registry Key Resource

```puppet
# Ensure a key exists
registry_key { 'HKLM\SOFTWARE\MyApp':
  ensure => present,
}

# Ensure a key and all its parents exist (purge removes keys not in Puppet)
registry_key { 'HKLM\SOFTWARE\MyApp\Settings\Advanced':
  ensure => present,
}

# Remove a key (and all its values)
registry_key { 'HKLM\SOFTWARE\OldApp':
  ensure => absent,
}
```

### 14.2 Registry Value Resource

```puppet
# REG_SZ (string)
registry_value { 'HKLM\SOFTWARE\MyApp\Version':
  ensure => present,
  type   => string,
  data   => '3.1.0',
}

# REG_DWORD
registry_value { 'HKLM\SOFTWARE\MyApp\MaxConnections':
  ensure => present,
  type   => dword,
  data   => 50,
}

# REG_QWORD (64-bit integer)
registry_value { 'HKLM\SOFTWARE\MyApp\MaxBytes':
  ensure => present,
  type   => qword,
  data   => 10737418240,   # 10 GB
}

# REG_EXPAND_SZ (expandable string — %VARS% resolved by Windows)
registry_value { 'HKLM\SOFTWARE\MyApp\LogDir':
  ensure => present,
  type   => expand,
  data   => '%TEMP%\MyApp\Logs',
}

# REG_MULTI_SZ (multi-line string)
registry_value { 'HKLM\SOFTWARE\MyApp\AllowedHosts':
  ensure => present,
  type   => array,
  data   => ['server1.example.com', 'server2.example.com', 'server3.example.com'],
}

# REG_BINARY
registry_value { 'HKLM\SOFTWARE\MyApp\BinaryConfig':
  ensure => present,
  type   => binary,
  data   => 'DEADBEEF0102',   # hex string, no spaces
}

# Remove a value
registry_value { 'HKLM\SOFTWARE\MyApp\OldSetting':
  ensure => absent,
}
```

### 14.3 HIVE Shortcuts

| Puppet Prefix | Full Registry Hive |
|---|---|
| `HKLM` | `HKEY_LOCAL_MACHINE` |
| `HKCU` | `HKEY_CURRENT_USER` (agent's user context — usually SYSTEM) |
| `HKCR` | `HKEY_CLASSES_ROOT` |
| `HKU` | `HKEY_USERS` |
| `HKPD` | `HKEY_PERFORMANCE_DATA` |

> **32-bit vs. 64-bit registry:** On 64-bit Windows, there is a 32-bit registry view under `SOFTWARE\Wow6432Node`. The `puppetlabs-registry` module always writes to the 64-bit view unless you specify the 32-bit path explicitly.

### 14.4 Registry Ordering

When a value's parent key must be created first, use `require`:

```puppet
registry_key { 'HKLM\SOFTWARE\MyApp': ensure => present }
registry_key { 'HKLM\SOFTWARE\MyApp\Settings': ensure => present, require => Registry_key['HKLM\SOFTWARE\MyApp'] }

registry_value { 'HKLM\SOFTWARE\MyApp\Settings\Timeout':
  ensure  => present,
  type    => dword,
  data    => 30,
  require => Registry_key['HKLM\SOFTWARE\MyApp\Settings'],
}
```

---

## 15. Managing Services and the SCM

### 15.1 Basic Service Management

```puppet
# Running and enabled (starts on boot)
service { 'W3SVC':           # IIS
  ensure => running,
  enable => true,
}

# Stopped and disabled
service { 'RemoteRegistry':
  ensure => stopped,
  enable => false,
}

# Trigger a service restart when a config file changes
service { 'MyAppService':
  ensure    => running,
  enable    => true,
  subscribe => File['C:/ProgramData/MyApp/config.ini'],
}
```

### 15.2 The `enable` Parameter on Windows

| Puppet `enable` | Windows SCM Start Type |
|---|---|
| `true` | Automatic |
| `false` | Disabled |
| `manual` | Manual |
| `delayed` | Automatic (Delayed Start) |

```puppet
service { 'wuauserv':        # Windows Update
  ensure => running,
  enable => delayed,         # Automatic (Delayed Start)
}
```

### 15.3 Managing a Service Account

```puppet
# Create the service account first
user { 'svcMyApp':
  ensure   => present,
  password => Sensitive(lookup('myapp::svc_password')),
  comment  => 'MyApp service account — managed by Puppet',
}

# Grant "Log on as a service" right via a PowerShell exec
exec { 'grant-logon-as-service-svcMyApp':
  command  => @(PS/L)
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        'svcMyApp', 'FullControl', 'Allow')
    # Use ntrights.exe or secedit to grant SeServiceLogonRight
    $infContent = "[Version]`r`nSignature=`"`$CHICAGO$`"`r`n[Privilege Rights]`r`nSeServiceLogonRight = *S-1-5-32-544,svcMyApp"
    $infPath = "$env:TEMP\grant_logon.inf"
    $dbPath  = "$env:TEMP\grant_logon.sdb"
    Set-Content -Path $infPath -Value $infContent
    secedit /configure /db $dbPath /cfg $infPath /quiet
    | PS
  provider => powershell,
  unless   => @(PS/L)
    $rights = secedit /export /cfg "$env:TEMP\secpol.cfg" /areas USER_RIGHTS 2>&1
    if (Select-String -Path "$env:TEMP\secpol.cfg" -Pattern 'SeServiceLogonRight.*svcMyApp') { exit 0 } else { exit 1 }
    | PS
  require  => User['svcMyApp'],
}
```

---

## 16. Managing Local Users and Groups

### 16.1 Users

```puppet
# Create a local user
user { 'appuser':
  ensure     => present,
  password   => Sensitive(lookup('myapp::appuser_password')),
  comment    => 'Application user',
  managehome => false,
}

# Create a local user and add to groups
user { 'deployer':
  ensure   => present,
  password => Sensitive('Str0ng!Pass'),
  groups   => ['Administrators'],
  comment  => 'Deployment service account',
}

# Remove a user
user { 'tempuser':
  ensure => absent,
}
```

> **Password security:** Always use `Sensitive()` to prevent passwords appearing in reports, logs, and the PuppetDB. In production, store passwords in Hiera with `eyaml` encryption:
> ```yaml
> # data/nodes/win01.example.com.yaml
> myapp::svc_password: >
>   ENC[PKCS7,MIIBiAYJKoZIhvcNAQcDoIIBeTCCA...]
> ```

### 16.2 Groups

```puppet
# Create a local group
group { 'AppAdmins':
  ensure  => present,
  members => ['appuser', 'deployer'],
}

# Add a domain user to the local Administrators group
group { 'Administrators':
  ensure  => present,
  members => ['DOMAIN\AppTeam', 'DOMAIN\AppAdmin'],
}

# Create group, ensure members (without removing others)
group { 'WebUsers':
  ensure          => present,
  members         => ['DOMAIN\WebAppSvc'],
  auth_membership => false,   # don't remove existing members not listed here
}
```

---

## 17. Environment Variables

```puppet
# Set a system-level environment variable
windows_env { 'MY_APP_HOME':
  ensure    => present,
  value     => 'C:\Program Files\MyApp',
  mergemode => clobber,    # replace existing value
}

# Append to PATH without removing existing entries
windows_env { 'PATH=C:\Program Files\MyApp\bin':
  ensure    => present,
  mergemode => insert,
}

# Prepend to PATH (highest priority)
windows_env { 'PATH=C:\Program Files\MyApp\bin':
  ensure    => present,
  mergemode => prepend,
}

# Remove a specific entry from PATH
windows_env { 'PATH=C:\OldApp\bin':
  ensure => absent,
}

# Remove an entire variable
windows_env { 'OBSOLETE_VAR':
  ensure => absent,
}

# Set a user-level variable (for a named user)
windows_env { 'EDITOR':
  ensure    => present,
  value     => 'notepad',
  user      => 'developer',
  mergemode => clobber,
}
```

> **Note:** Changes to system environment variables take effect for new processes. Existing processes (including the current PowerShell session) will not see the changes until they restart. The Puppet agent service reads environment variables at start — restart the service after changing PATH.

---

## 18. Running PowerShell from Puppet

### 18.1 The `powershell` Provider

Requires `puppetlabs-powershell`:

```puppet
exec { 'set-timezone':
  command  => 'Set-TimeZone -Name "W. Europe Standard Time"',
  provider => powershell,
  unless   => 'if ((Get-TimeZone).Id -eq "W. Europe Standard Time") { exit 0 } else { exit 1 }',
}
```

### 18.2 Always Provide an Idempotency Guard

`exec` without a guard runs on **every** Puppet run and breaks idempotency. Use one of:

- **`unless`** — run the command unless this PowerShell exits 0
- **`onlyif`** — run the command only if this PowerShell exits 0
- **`creates`** — run the command only if this file/path does not exist
- **`refreshonly => true`** — run only when notified by another resource

```puppet
# creates — runs once when the target file doesn't exist
exec { 'initialize-database':
  command   => 'C:/Scripts/init-db.ps1',
  provider  => powershell,
  creates   => 'C:/ProgramData/MyApp/.initialized',
}

# refreshonly — runs only when config file changes
exec { 'restart-app-gracefully':
  command     => 'Restart-Service MyApp -Force',
  provider    => powershell,
  refreshonly => true,
  subscribe   => File['C:/ProgramData/MyApp/config.ini'],
}
```

### 18.3 Multi-Line Commands with Heredoc

```puppet
exec { 'configure-winrm-https':
  command  => @("PS"/L),
    $cert = New-SelfSignedCertificate -DnsName $env:COMPUTERNAME `
              -CertStoreLocation Cert:\LocalMachine\My
    New-WSManInstance -ResourceURI winrm/config/listener `
      -SelectorSet @{Transport="HTTPS";Address="*"} `
      -ValueSet @{CertificateThumbprint=$cert.Thumbprint}
    Set-WSManInstance -ResourceURI winrm/config/service `
      -ValueSet @{AllowUnencrypted=$false}
    | PS
  provider => powershell,
  unless   => @(PS/L),
    $l = Get-WSManInstance winrm/config/listener `
           -SelectorSet @{Transport="HTTPS";Address="*"} -EA SilentlyContinue
    if ($l) { exit 0 } else { exit 1 }
    | PS
}
```

### 18.4 Execution Policy in `exec`

If the execution policy is restrictive, call PowerShell with `-ExecutionPolicy Bypass`:

```puppet
exec { 'run-setup-script':
  command  => 'powershell.exe -ExecutionPolicy Bypass -File C:\Scripts\setup.ps1',
  creates  => 'C:\ProgramData\MyApp\.setup_done',
}
```

---

## 19. IIS Management

### 19.1 Install IIS

```puppet
# Install IIS and basic features via dsc_windowsfeature
['Web-Server', 'Web-Asp-Net45', 'Web-Mgmt-Console', 'Web-Http-Logging'].each |$feature| {
  dsc_windowsfeature { $feature:
    dsc_ensure => 'Present',
    dsc_name   => $feature,
  }
}

# Or with the puppetlabs-iis module (installs IIS automatically)
include iis
```

### 19.2 Application Pools

```puppet
iis_application_pool { 'MyAppPool':
  ensure                    => present,
  state                     => started,
  managed_runtime_version   => 'v4.0',
  managed_pipeline_mode     => 'Integrated',
  identity_type             => 'ApplicationPoolIdentity',
  start_mode                => 'AlwaysRunning',
  idle_timeout              => '00:00:00',     # 0 = never idle out
  periodic_restart_time     => '02:00:00',     # recycle at 2am
  max_processes             => 1,
  rapid_fail_protection     => true,
  rapid_fail_protection_max_crashes  => 5,
  rapid_fail_protection_interval     => '00:05:00',
}
```

### 19.3 Websites

```puppet
iis_site { 'MyApp':
  ensure          => present,
  physpath        => 'C:/inetpub/MyApp',
  bindings        => [
    { protocol => 'http',  port => 80,  hostheader => 'myapp.example.com' },
    { protocol => 'https', port => 443, hostheader => 'myapp.example.com',
      certificatestorename => 'MY',
      certificatehash      => lookup('myapp::ssl_thumbprint') },
  ],
  applicationpool => 'MyAppPool',
  logformat       => 'W3C',
  logpath         => 'C:/inetpub/logs/MyApp',
  require         => Iis_application_pool['MyAppPool'],
}
```

### 19.4 Applications and Virtual Directories

```puppet
iis_application { 'api':
  ensure          => present,
  sitename        => 'MyApp',
  physpath        => 'C:/inetpub/MyApp/api',
  applicationpool => 'ApiPool',
}

iis_virtual_directory { 'uploads':
  ensure   => present,
  sitename => 'MyApp',
  physpath => 'D:/Uploads',
}
```

---

## 20. DSC (Desired State Configuration) Integration

### 20.1 How the Bridge Works

The `puppet-dsc_lite` module translates Puppet resource declarations into `Invoke-DscResource` PowerShell calls. Puppet handles the three-phase cycle:

1. **GET** — read current state of the Windows resource
2. **TEST** — compare current to desired state
3. **SET** — apply changes if TEST returns `$false`

This is fully idempotent. Puppet applies changes only when drift is detected.

### 20.2 `dsc_lite` — Generic Bridge

```puppet
# Install a Windows Feature
dsc { 'feature-web-server':
  resource_name => 'WindowsFeature',
  module        => 'PSDesiredStateConfiguration',
  properties    => {
    ensure => 'Present',
    name   => 'Web-Server',
  },
}

# Configure a registry key via DSC
dsc { 'registry-myapp-version':
  resource_name => 'Registry',
  module        => 'PSDesiredStateConfiguration',
  properties    => {
    ensure    => 'Present',
    key       => 'HKEY_LOCAL_MACHINE\SOFTWARE\MyApp',
    valuename => 'Version',
    valuedata => ['3.0.0'],
    valuetype => 'String',
  },
}
```

### 20.3 `dsc_windowsfeature` (auto-generated module)

```puppet
# Single feature
dsc_windowsfeature { 'IIS':
  dsc_ensure                => 'Present',
  dsc_name                  => 'Web-Server',
  dsc_includeallsubfeature  => false,
}

# Multiple features
$iis_features = [
  'Web-Server',
  'Web-Asp-Net45',
  'Web-Net-Ext45',
  'Web-ISAPI-Ext',
  'Web-ISAPI-Filter',
  'Web-Mgmt-Console',
  'Web-Http-Logging',
  'Web-Stat-Compression',
  'Web-Http-Redirect',
]

$iis_features.each |$feature| {
  dsc_windowsfeature { $feature:
    dsc_ensure => 'Present',
    dsc_name   => $feature,
  }
}
```

### 20.4 Pre-Installing PSGallery DSC Modules on Windows Nodes

Auto-generated `dsc_*` modules require the corresponding PowerShell DSC module on the Windows node. Install them via Puppet:

```puppet
exec { 'install-xWebAdministration-dsc-module':
  command  => 'Install-Module -Name xWebAdministration -RequiredVersion 3.3.0 -Force -Scope AllUsers',
  provider => powershell,
  unless   => 'if (Get-Module -Name xWebAdministration -ListAvailable | Where-Object { $_.Version -eq "3.3.0" }) { exit 0 } else { exit 1 }',
}
```

Or bake PSGallery modules into your base image.

### 20.5 Decision: DSC vs. Native Puppet Resources

| Resource need | Use |
|---|---|
| File, user, group, service, package | Native Puppet resources |
| NTFS ACLs | `puppetlabs-acl` |
| Registry | `puppetlabs-registry` |
| Windows Features | `dsc_windowsfeature` |
| IIS sites/pools | `puppetlabs-iis` |
| SQL Server | `puppet-sqlserver_dsc` |
| Active Directory | `dsc_lite` + ActiveDirectoryDsc |
| Anything in PSGallery without a Forge module | `dsc_lite` |

---

## 21. Windows Facts and Conditional Manifests

### 21.1 Key Windows Facts

```powershell
# Run on the Windows node to explore facts
facter -j | python -m json.tool | head -100

# Key structured facts
facter os                          # OS details
facter os.windows                  # Windows-specific: edition, product_name, installation_type
facter kernel                      # 'windows'
facter os.release.full             # e.g., '10.0.20348'
facter processors.count            # CPU core count
facter memory.system.total_bytes   # RAM in bytes
facter networking                  # network interfaces, IP, FQDN
facter virtual                     # virtualization type: 'vmware', 'hyperv', 'physical', etc.
facter identity.privileged         # true if running as SYSTEM/Administrator
facter disks                       # disk sizes and types
```

### 21.2 Using Facts in Manifests

```puppet
# Branch on Windows edition
if $facts['os']['windows']['installation_type'] == 'Server' {
  include role::windows_server
} else {
  include role::windows_workstation
}

# Scale resources based on CPU count
$thread_count = $facts['processors']['count'] * 2
registry_value { 'HKLM\SOFTWARE\MyApp\WorkerThreads':
  ensure => present,
  type   => dword,
  data   => $thread_count,
}

# Apply extra hardening on physical nodes
if $facts['virtual'] == 'physical' {
  include profile::windows::physical_security
}

# Use Windows product name for version-specific behavior
case $facts['os']['windows']['product_name'] {
  /Server 2019/: { include profile::windows::server2019 }
  /Server 2022/: { include profile::windows::server2022 }
  /Windows 11/:  { include profile::windows::workstation }
  default:       { notify { 'unknown-windows-version': message => "Unrecognised: ${facts['os']['windows']['product_name']}" } }
}
```

### 21.3 Custom External Facts (PowerShell)

Place `.ps1` files in `modules/mymodule/facts.d/`:

```powershell
# modules/mymodule/facts.d/app_version.ps1
# Output format: KEY=VALUE (one per line)
$regPath = 'HKLM:\SOFTWARE\MyApp'
try {
    $version = (Get-ItemProperty -Path $regPath -Name Version -ErrorAction Stop).Version
    Write-Output "myapp_version=$version"
    Write-Output "myapp_installed=true"
} catch {
    Write-Output "myapp_version=none"
    Write-Output "myapp_installed=false"
}
```

Puppet automatically syncs `facts.d` files to the agent before each run.

### 21.4 Custom Facts in Ruby (Cross-Platform)

```ruby
# modules/mymodule/lib/facter/myapp_state.rb
Facter.add('myapp_state') do
  confine :kernel => 'windows'

  setcode do
    require 'win32/registry'
    begin
      Win32::Registry::HKEY_LOCAL_MACHINE.open('SOFTWARE\MyApp') do |reg|
        {
          'version'     => reg.read_s('Version'),
          'install_dir' => reg.read_s('InstallDir'),
          'licensed'    => reg.read_i('Licensed') == 1,
        }
      end
    rescue Win32::Registry::Error
      { 'installed' => false }
    end
  end
end
```

---

## 22. Cross-Platform Module Design

### 22.1 The Platform Detection Pattern

```puppet
# In the main class or a shared helper
$is_windows = $facts['kernel'] == 'windows'
$is_linux   = $facts['kernel'] == 'Linux'

# Platform-specific variables via a selector
$cfg_dir = $facts['kernel'] ? {
  'windows' => 'C:/ProgramData/MyApp',
  'Linux'   => '/etc/myapp',
  default   => fail("Unsupported kernel: ${facts['kernel']}"),
}

$pkg_name = $facts['kernel'] ? {
  'windows' => 'MyApp',      # Chocolatey package name
  'Linux'   => 'myapp',      # apt/yum package name
}

$svc_name = $facts['kernel'] ? {
  'windows' => 'MyAppService',
  'Linux'   => 'myapp',
}

# Then use the variables — identical resource declaration on both platforms
package { $pkg_name: ensure => installed }
service { $svc_name: ensure => running, enable => true }
file { "${cfg_dir}/config.ini": ensure => file, content => $config_content }
```

### 22.2 Sub-Class Delegation (Cleanest Pattern)

```puppet
# manifests/init.pp
class myapp (
  String $version = 'installed',
) {
  # Common setup
  class { 'myapp::install': version => $version }
    -> class { 'myapp::config': }
    ~> class { 'myapp::service': }
}

# manifests/install.pp
class myapp::install (String $version) {
  case $facts['kernel'] {
    'windows': { include myapp::install::windows }
    'Linux':   { include myapp::install::linux }
    default:   { fail("myapp does not support kernel: ${facts['kernel']}") }
  }
}

# manifests/install/windows.pp — all Windows install logic here
class myapp::install::windows {
  require chocolatey

  package { 'MyApp':
    ensure   => $myapp::install::version,
    provider => chocolatey,
  }
}

# manifests/install/linux.pp — all Linux install logic here
class myapp::install::linux {
  package { 'myapp':
    ensure => $myapp::install::version,
  }
}
```

### 22.3 EPP Templates on Both Platforms

EPP templates work identically. Use Puppet variables to provide platform-specific paths:

```puppet
# The template call is identical on both platforms
file { "${myapp::cfg_dir}/config.ini":
  ensure  => file,
  content => epp('myapp/config.ini.epp', {
    db_host  => $db_host,
    cfg_dir  => $myapp::cfg_dir,
    log_dir  => $myapp::log_dir,
    platform => $facts['kernel'],
  }),
}
```

```
<%- | String $db_host,
      String $cfg_dir,
      String $log_dir,
      String $platform,
| -%>
# Managed by Puppet on <%= $platform %>
[database]
host = <%= $db_host %>

[paths]
config = <%= $cfg_dir %>
logs   = <%= $log_dir %>
```

---

## 23. Hiera Data for Windows

### 23.1 Hierarchy with Windows Tier

```yaml
# /etc/puppetlabs/code/environments/production/hiera.yaml
---
version: 5
hierarchy:
  - name: "Node-specific"
    path: "data/nodes/%{trusted.certname}.yaml"

  - name: "Role"
    path: "data/roles/%{facts.puppet_role}.yaml"

  - name: "OS family"
    path: "data/os/%{facts.os.family}.yaml"

  - name: "Kernel (windows / Linux)"
    path: "data/kernel/%{facts.kernel}.yaml"

  - name: "Environment"
    path: "data/environments/%{environment}.yaml"

  - name: "Common"
    path: "data/common.yaml"

defaults:
  data_hash: yaml_data
  datadir: /etc/puppetlabs/code/environments/production
```

### 23.2 Example Data Files

```yaml
# data/kernel/windows.yaml
profile::base::packages:
  - '7zip'
  - 'notepadplusplus'
  - 'putty'
  - 'googlechrome'

profile::base::services_disabled:
  - 'RemoteRegistry'
  - 'Fax'
  - 'XblAuthManager'

chocolatey::source: 'https://nexus.example.com/repository/choco/'
```

```yaml
# data/kernel/Linux.yaml
profile::base::packages:
  - 'vim'
  - 'curl'
  - 'htop'
  - 'tmux'
  - 'jq'

profile::base::services_disabled:
  - 'telnet'
  - 'rsh'
```

```yaml
# data/common.yaml
profile::base::ntp_servers:
  - '0.pool.ntp.org'
  - '1.pool.ntp.org'
  - '2.pool.ntp.org'
```

### 23.3 Sensitive Data (eyaml)

```bash
# Install hiera-eyaml on the Puppet Server
sudo /opt/puppetlabs/puppet/bin/gem install hiera-eyaml

# Generate keys
sudo /opt/puppetlabs/puppet/bin/eyaml createkeys \
  --pkcs7-private-key=/etc/puppetlabs/puppet/eyaml/private_key.pkcs7.pem \
  --pkcs7-public-key=/etc/puppetlabs/puppet/eyaml/public_key.pkcs7.pem

# Encrypt a secret
sudo /opt/puppetlabs/puppet/bin/eyaml encrypt \
  --pkcs7-public-key=/etc/puppetlabs/puppet/eyaml/public_key.pkcs7.pem \
  --string 'Str0ng!P@ssw0rd'
```

```yaml
# data/nodes/win01.example.com.yaml
myapp::svc_password: ENC[PKCS7,MIIBiAYJKoZIhvcNAQcDoIIBeTCCA...]
```

```puppet
# In a manifest — eyaml decryption is transparent
user { 'svcMyApp':
  ensure   => present,
  password => Sensitive(lookup('myapp::svc_password')),
}
```

---

## 24. Puppet Bolt on Windows

Puppet Bolt runs **agentless** tasks against Windows nodes using WinRM or SSH.

### 24.1 Install Bolt on the Control Node

```bash
# On Linux / macOS (control node)
# Add the Puppet platform repo (same as puppet-agent)
sudo apt-get install -y puppet-bolt      # Ubuntu
sudo dnf install -y puppet-bolt          # Rocky/RHEL
```

### 24.2 Configure WinRM on Windows Targets

```powershell
# On the Windows target — enable WinRM with HTTP (lab only)
Enable-PSRemoting -Force
winrm set winrm/config/client/auth '@{Basic="true"}'
winrm set winrm/config/service/auth '@{Basic="true"}'
winrm set winrm/config/service '@{AllowUnencrypted="true"}'

# For production — use HTTPS with a real certificate:
# Create a listener with a certificate thumbprint
$cert = Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -like "*$env:COMPUTERNAME*" } | Select -First 1
New-WSManInstance -ResourceURI winrm/config/listener `
    -SelectorSet @{Transport="HTTPS";Address="*"} `
    -ValueSet @{CertificateThumbprint=$cert.Thumbprint}
```

Allow WinRM through Windows Firewall:

```powershell
# HTTP (lab — port 5985)
Enable-NetFirewallRule -Name "WINRM-HTTP-In-TCP"

# HTTPS (production — port 5986)
New-NetFirewallRule -DisplayName "WinRM HTTPS" -Direction Inbound `
    -Protocol TCP -LocalPort 5986 -Action Allow
```

### 24.3 Bolt Inventory File

```yaml
# inventory.yaml
targets:
  - name: windows
    targets:
      - win01.example.com
      - win02.example.com
    config:
      transport: winrm
      winrm:
        user: Administrator
        password: "${env:WIN_ADMIN_PASSWORD}"
        ssl: true
        ssl-verify: false   # set true in production with a proper CA
```

### 24.4 Running Bolt Commands Against Windows

```bash
# Run a PowerShell command on all Windows targets
bolt command run 'Get-ComputerInfo | Select-Object OsName, OsVersion' \
  --targets windows --inventory inventory.yaml

# Run a PowerShell script
bolt script run scripts/check-services.ps1 \
  --targets windows --inventory inventory.yaml

# Apply a Puppet manifest to targets without an agent
bolt apply manifests/baseline.pp \
  --targets windows --inventory inventory.yaml

# Run a Puppet task
bolt task run chocolatey::install package=git \
  --targets windows --inventory inventory.yaml
```

---

## 25. Autosigning for Windows Nodes

In large estates, manually signing every certificate is not practical.

### 25.1 Policy-Based Autosigning (Recommended)

Create an autosign script that validates the CSR based on trusted attributes:

```bash
# /etc/puppetlabs/puppet/autosign.rb
#!/opt/puppetlabs/puppet/bin/ruby
require 'puppet/ssl/certificate_request'

certname = ARGV[0]
csr_pem  = STDIN.read
csr      = Puppet::SSL::CertificateRequest.from_s(csr_pem)

# Only auto-sign nodes with certnames matching our naming convention
if certname =~ /\A(win|web|db|app)\d+\.(dev|test|prod)\.example\.com\z/
  exit 0   # allow
else
  exit 1   # deny
end
```

Configure the server to use it:

```bash
sudo chmod 0755 /etc/puppetlabs/puppet/autosign.rb

# puppet.conf on the server:
# [master]
# autosign = /etc/puppetlabs/puppet/autosign.rb
sudo puppet config set autosign /etc/puppetlabs/puppet/autosign.rb --section master
sudo systemctl restart puppetserver
```

### 25.2 CSR Attributes for Autosigning

Embed a pre-shared token in the CSR to validate it came from an authorised provisioning system:

```yaml
# On the Windows node, before first run:
# C:\ProgramData\PuppetLabs\puppet\etc\csr_attributes.yaml
custom_attributes:
  challengePassword: "my-provisioning-secret-token"
extension_requests:
  pp_role: "webserver"
  pp_environment: "production"
  pp_datacenter: "eu-west-1"
```

```ruby
# autosign.rb — check the challenge password
custom_attrs = csr.custom_attributes
token = custom_attrs.find { |a| a['oid'] == '1.2.840.113549.1.9.7' }&.dig('value')
exit(token == 'my-provisioning-secret-token' ? 0 : 1)
```

### 25.3 Simple Autosign (Development Only)

```bash
# puppet.conf — NEVER use in production
[master]
autosign = true
```

---

## 26. Running the Agent as a Non-SYSTEM Account

By default the Puppet agent runs as `NT AUTHORITY\SYSTEM`. For production security, use a dedicated service account.

### 26.1 Create the Service Account

```puppet
user { 'PuppetAgent':
  ensure   => present,
  password => Sensitive(lookup('puppet::agent_password')),
  comment  => 'Puppet Agent service account',
  groups   => [],
}
```

Grant the account the right to log on as a service (via Group Policy or `ntrights.exe`).

### 26.2 Reconfigure the Service

```powershell
# Change the service account after installation
$svcName = 'puppet'
$domain  = '.'                          # local account — use 'DOMAIN' for domain accounts
$user    = 'PuppetAgent'
$pass    = 'Str0ng!SvcP@ss'

$svc = Get-WmiObject Win32_Service -Filter "Name='$svcName'"
$svc.Change($null,$null,$null,$null,$null,$null,"$domain\$user",$pass)
Restart-Service $svcName
```

Or set during installation:

```powershell
msiexec /qn /i puppet-agent.msi `
  PUPPET_SERVER=puppet.example.com `
  PUPPET_AGENT_ACCOUNT_USER=PuppetAgent `
  PUPPET_AGENT_ACCOUNT_PASSWORD=Str0ng!SvcP@ss `
  PUPPET_AGENT_ACCOUNT_DOMAIN=.
```

### 26.3 File Permissions for the Service Account

The service account needs read access to `puppet.conf` and the SSL directory:

```puppet
acl { 'C:/ProgramData/PuppetLabs/puppet/etc':
  purge       => false,
  permissions => [
    {
      identity => 'PuppetAgent',
      rights   => ['read'],
      affects  => 'all',
    },
  ],
}
```

---

## 27. Security Hardening Reference

### 27.1 Puppet Agent Hardening

```puppet
# Ensure agent config is not world-readable
acl { 'C:/ProgramData/PuppetLabs/puppet/etc/puppet.conf':
  purge       => true,
  permissions => [
    { identity => 'SYSTEM',         rights => ['full'] },
    { identity => 'Administrators', rights => ['full'] },
    { identity => 'PuppetAgent',    rights => ['read'] },
  ],
}

# Protect the private key
acl { 'C:/ProgramData/PuppetLabs/puppet/etc/ssl/private_keys':
  purge                      => true,
  inherit_parent_permissions => false,
  permissions                => [
    { identity => 'SYSTEM',      rights => ['full'] },
    { identity => 'PuppetAgent', rights => ['read'] },
  ],
}
```

### 27.2 Windows OS Hardening via Puppet

```puppet
class profile::windows::hardening {

  # Disable SMBv1 (WannaCry / NotPetya vector)
  registry_value { 'HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters\SMB1':
    ensure => present, type => dword, data => 0,
  }

  # Enforce TLS 1.2+ only
  $tls_keys = {
    'SSL 2.0' => 0, 'SSL 3.0' => 0,
    'TLS 1.0' => 0, 'TLS 1.1' => 0,
  }
  $tls_keys.each |$proto, $enabled| {
    registry_key  { "HKLM\\SYSTEM\\CurrentControlSet\\Control\\SecurityProviders\\SCHANNEL\\Protocols\\${proto}\\Server":
      ensure => present,
    }
    registry_value { "HKLM\\SYSTEM\\CurrentControlSet\\Control\\SecurityProviders\\SCHANNEL\\Protocols\\${proto}\\Server\\Enabled":
      ensure  => present, type => dword, data => $enabled,
      require => Registry_key["HKLM\\SYSTEM\\CurrentControlSet\\Control\\SecurityProviders\\SCHANNEL\\Protocols\\${proto}\\Server"],
    }
  }
  registry_key  { 'HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server':
    ensure => present,
  }
  registry_value { 'HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server\Enabled':
    ensure => present, type => dword, data => 1,
    require => Registry_key['HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server'],
  }

  # Disable Autorun on all drives
  registry_value { 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer\NoDriveTypeAutoRun':
    ensure => present, type => dword, data => 255,
  }

  # Disable LLMNR (used in NBNS/LLMNR spoofing attacks)
  registry_key  { 'HKLM\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient': ensure => present }
  registry_value { 'HKLM\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient\EnableMulticast':
    ensure  => present, type => dword, data => 0,
    require => Registry_key['HKLM\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient'],
  }

  # Disable insecure services
  ['RemoteRegistry', 'Telnet', 'SNMP'].each |$svc| {
    service { $svc:
      ensure => stopped,
      enable => false,
    }
  }
}
```

### 27.3 Password Security Checklist

- [ ] Never hardcode passwords in Puppet manifests or Hiera plain YAML
- [ ] Always wrap passwords in `Sensitive()`: `password => Sensitive($pwd)`
- [ ] Encrypt secrets in Hiera with `eyaml` (PKCS7 or AWS KMS backend)
- [ ] Rotate the eyaml encryption keys annually
- [ ] Service accounts should have minimum required permissions
- [ ] Audit `C:\ProgramData\PuppetLabs\puppet\cache\` — reports may contain resource titles that reveal configuration

---

## 28. Troubleshooting

### 28.1 Certificate Problems

**Symptom:** `SSL_connect returned=1 errno=0 state=error: certificate verify failed`

```powershell
# Clean SSL state on the agent
$sslDir = 'C:\ProgramData\PuppetLabs\puppet\etc\ssl'
Remove-Item -Path $sslDir -Recurse -Force
puppet agent --test   # re-generates keys and CSR
```

```bash
# On the server — clean the old cert and re-sign
sudo puppetserver ca clean --certname win01.example.com
sudo puppetserver ca sign --certname win01.example.com
```

**Symptom:** `hostname was not match with the server certificate`

The agent's `certname` does not match what the certificate was issued for. Check:
```powershell
puppet config print certname
openssl x509 -in 'C:\ProgramData\PuppetLabs\puppet\etc\ssl\certs\win01.example.com.pem' -noout -subject
```

### 28.2 Connectivity Problems

**Symptom:** `Could not retrieve catalog from remote server: Error 400`

```powershell
# Verify network path
Test-NetConnection -ComputerName puppet.example.com -Port 8140 -InformationLevel Detailed

# Verify DNS resolution
Resolve-DnsName puppet.example.com

# Check puppet.conf has the correct server
puppet config print server
```

**Symptom:** `Connection refused on port 8140`

```bash
# On the Puppet Server — is the service running?
sudo systemctl status puppetserver
sudo ss -tlnp | grep 8140

# Check for JVM OOM (Out of Memory) errors
sudo journalctl -u puppetserver --since "1 hour ago" | grep -i 'error\|oom\|killed'
```

### 28.3 Module/Class Not Found

**Symptom:** `Could not find class chocolatey`

```bash
# On the server — verify the module is installed
puppet module list | grep chocolatey

# If missing
sudo puppet module install puppetlabs-chocolatey

# Restart puppetserver to pick up the new module
sudo systemctl restart puppetserver
```

### 28.4 Chocolatey Installation Fails

**Symptom:** `choco.exe: command not found` or Chocolatey class fails

```powershell
# Manually trigger the Chocolatey install script to see errors
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
```

**Common causes:**
- TLS 1.2 not enforced → `[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12`
- Proxy blocking chocolatey.org → set proxy in Chocolatey config or use internal mirror
- PowerShell execution policy → `Set-ExecutionPolicy RemoteSigned -Scope LocalMachine`

### 28.5 Registry Resource Not Applied

**Symptom:** Registry changes appear in Puppet output but are not applied / revert immediately

This is usually caused by a **Group Policy Object (GPO)** overwriting the registry value. GPO wins over Puppet on domain-joined machines.

Diagnoses:
```powershell
gpresult /h C:\gpreport.html
# Open in browser — look for policies overriding the same key
```

Solution: Either configure the GPO to match Puppet's desired state (preferred) or use Puppet to manage the GPO via DSC's `PolicyFileEditor`.

### 28.6 Debugging Puppet Runs

```powershell
# Full debug output
puppet agent --test --debug 2>&1 | Tee-Object -FilePath C:\puppet-debug.log

# Just show timing of each resource
puppet agent --test --evaltrace

# Show only failures
puppet agent --test 2>&1 | Select-String 'Error|Failed|Warning'

# Check the compiled catalog (what the server sent)
$catalog = Get-Content 'C:\ProgramData\PuppetLabs\puppet\cache\catalog\win01.example.com.json' -Raw
$catalog | python -m json.tool | Select-String '"type"'
```

### 28.7 Common Error Messages Reference

| Error Message | Likely Cause | Fix |
|---|---|---|
| `Could not find class X` | Module not installed on server | `puppet module install X` on server |
| `No such file or directory` | File resource path wrong | Check path, forward slashes |
| `Access denied` | Agent running as SYSTEM lacks permission | Run as elevated or set explicit ACL |
| `SSL peer certificate not verified` | CA mismatch | Clean SSL dir, re-bootstrap |
| `execution expired` | Server unreachable (timeout) | Check firewall, DNS, server health |
| `Parameter X failed on ...` | Wrong type for a resource parameter | Check data type (string vs integer) |
| `Duplicate resource declaration` | Two resources with same title | Add `unless defined(...)` guard |
| `Catalog compilation failed` | Puppet code syntax error | Run `puppet parser validate manifests/` on server |

---

## 29. Quick Reference Cheat Sheet

### Agent Commands (run as Administrator)

```powershell
# Apply catalog
puppet agent --test

# Dry run
puppet agent --test --noop

# Apply specific environment
puppet agent --test --environment staging

# Debug mode
puppet agent --test --debug

# Check configuration
puppet config print

# Show certificate fingerprint
puppet ssl fingerprint

# Clean SSL and re-bootstrap
Remove-Item 'C:\ProgramData\PuppetLabs\puppet\etc\ssl' -Recurse -Force
puppet agent --test

# Service management
Start-Service puppet
Stop-Service puppet
Restart-Service puppet
Set-Service puppet -StartupType Automatic
```

### Server Commands (run as root on Linux)

```bash
# Certificate management
puppetserver ca list                             # pending requests
puppetserver ca list --all                      # all certs
puppetserver ca sign --certname win01.example.com
puppetserver ca sign --all
puppetserver ca revoke --certname win01.example.com
puppetserver ca clean --certname win01.example.com

# Module management
puppet module install puppetlabs-chocolatey
puppet module install puppetlabs-registry
puppet module install puppetlabs-acl
puppet module install puppet-windows_env
puppet module install puppetlabs-iis
puppet module install puppet-windowsfeature
puppet module list

# Server service
systemctl start puppetserver
systemctl stop puppetserver
systemctl restart puppetserver
systemctl status puppetserver
journalctl -u puppetserver -f

# Compile a catalog manually (debug)
puppet catalog compile win01.example.com
```

### Key File Locations

| File | Windows Path | Purpose |
|---|---|---|
| `puppet.conf` | `C:\ProgramData\PuppetLabs\puppet\etc\puppet.conf` | Agent configuration |
| Agent certificate | `C:\ProgramData\PuppetLabs\puppet\etc\ssl\certs\<certname>.pem` | Signed TLS cert |
| Private key | `C:\ProgramData\PuppetLabs\puppet\etc\ssl\private_keys\<certname>.pem` | Agent TLS key |
| Last catalog | `C:\ProgramData\PuppetLabs\puppet\cache\catalog\<certname>.json` | Cached catalog |
| Run summary | `C:\ProgramData\PuppetLabs\puppet\cache\state\last_run_summary.yaml` | Last run stats |
| External facts | `C:\ProgramData\PuppetLabs\facter\facts.d\` | Custom external facts |
| Install log | `C:\Users\<user>\AppData\Local\Temp\puppet-install.log` | MSI install log |

### Resource Type Quick Reference for Windows

```puppet
# Package (Chocolatey)
package { 'git':    ensure => '2.43.0', provider => chocolatey }
package { 'telnet': ensure => absent,   provider => chocolatey }

# File
file { 'C:/App/config.ini':  ensure => file, content => epp('...') }
file { 'C:/App/data':        ensure => directory }
file { 'C:/App/old.conf':    ensure => absent }

# Service (SCM)
service { 'W3SVC':    ensure => running, enable => true }
service { 'Telnet':   ensure => stopped, enable => false }
service { 'wuauserv': ensure => running, enable => delayed }

# Registry
registry_key   { 'HKLM\SOFTWARE\App':          ensure => present }
registry_value { 'HKLM\SOFTWARE\App\Version':  ensure => present, type => string, data => '1.0' }
registry_value { 'HKLM\SOFTWARE\App\MaxConns': ensure => present, type => dword,  data => 10 }

# Users / Groups
user  { 'svcApp':    ensure => present, password => Sensitive('...') }
group { 'AppAdmins': ensure => present, members  => ['svcApp'] }

# ACL
acl { 'C:/App/secure': purge => true, permissions => [{ identity => 'SYSTEM', rights => ['full'] }] }

# Environment
windows_env { 'APP_HOME': ensure => present, value => 'C:\App', mergemode => clobber }
windows_env { 'PATH=C:\App\bin': ensure => present, mergemode => insert }

# PowerShell exec
exec { 'run-ps': command => 'Set-TimeZone -Name "W. Europe Standard Time"', provider => powershell,
       unless => 'if ((Get-TimeZone).Id -eq "W. Europe Standard Time") { exit 0 } else { exit 1 }' }

# DSC
dsc_windowsfeature { 'IIS': dsc_ensure => 'Present', dsc_name => 'Web-Server' }
dsc { 'my-dsc': resource_name => 'WindowsFeature', module => 'PSDesiredStateConfiguration',
      properties => { ensure => 'Present', name => 'Telnet-Client' } }
```

### Hiera Windows Data Pattern

```yaml
# data/kernel/windows.yaml
profile::base::packages:
  - '7zip'
  - 'notepadplusplus'
  - 'putty'
chocolatey::source: 'https://nexus.example.com/repository/chocolatey/'

# data/nodes/win01.example.com.yaml
myapp::svc_password: ENC[PKCS7,MIIBiA...]   # eyaml encrypted
windows_baseline::server_packages:
  - 'sysinternals'
  - 'winscp'
```

---

*Document maintained as part of the Puppet Base Course — Day 4: Windows with Puppet.*
*Last updated: 2026-06-09*
