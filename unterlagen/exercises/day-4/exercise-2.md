# Exercise 2 — Windows Resources: Chocolatey, Registry, Services, Files, and ACLs

**Estimated time:** 75–90 minutes

## Objective

Write production-quality Puppet code that manages the full breadth of Windows resources: install and configure Chocolatey, manage software packages, work with the Windows registry, control services, manage files with NTFS permissions, and use the `windows_env` resource. By the end you will have built a `windows_baseline` module that could form the foundation of a real enterprise Windows configuration.

---

## Prerequisites

- Exercise 1 completed — Windows node is connected to the Puppet Server
- The agent runs successfully and applies catalogs
- `puppetlabs-registry` module is installed on the server

---

## Part 1 — Create the Module Skeleton (5 min)

We will build a module called `windows_baseline`.

On the **Puppet Server** (Linux), create the module structure:

```bash
cd /etc/puppetlabs/code/environments/production/modules
mkdir -p windows_baseline/{manifests,files,templates,data}
```

Install all required modules on the server:

```bash
sudo puppet module install puppetlabs-chocolatey
sudo puppet module install puppetlabs-registry
sudo puppet module install puppetlabs-acl
sudo puppet module install puppet-windows_env
sudo puppet module install puppetlabs-powershell
```

Verify they are installed:

```bash
puppet module list | grep -E 'chocolatey|registry|acl|windows_env|powershell'
```

---

## Part 2 — Bootstrap Chocolatey (15 min)

### Step 1 — Create the init.pp main class

Create `/etc/puppetlabs/code/environments/production/modules/windows_baseline/manifests/init.pp`:

```puppet
# @summary Manages the complete Windows node baseline.
#
# @param chocolatey_source
#   URL of the primary Chocolatey package source.
# @param developer_packages
#   List of Chocolatey packages to install on developer nodes.
# @param server_packages
#   List of Chocolatey packages to install on server nodes.
class windows_baseline (
  String        $chocolatey_source   = 'https://chocolatey.org/api/v2',
  Array[String] $developer_packages  = [],
  Array[String] $server_packages     = [],
) {
  # Guard: only run on Windows
  unless $facts['kernel'] == 'windows' {
    fail("windows_baseline can only be applied to Windows nodes. Got: ${facts['kernel']}")
  }

  # Bootstrap Chocolatey first — everything else depends on it
  contain windows_baseline::chocolatey

  # Security hardening via the registry
  contain windows_baseline::registry_hardening

  # Baseline software packages
  contain windows_baseline::packages

  # Environment variables
  contain windows_baseline::env_vars

  # Ordering
  Class['windows_baseline::chocolatey']
    -> Class['windows_baseline::packages']
    -> Class['windows_baseline::registry_hardening']
    -> Class['windows_baseline::env_vars']
}
```

### Step 2 — Create the Chocolatey sub-class

Create `/etc/puppetlabs/code/environments/production/modules/windows_baseline/manifests/chocolatey.pp`:

```puppet
# @summary Installs and configures Chocolatey package manager.
class windows_baseline::chocolatey {

  # Install Chocolatey itself
  class { 'chocolatey':
    chocolatey_download_url => 'https://chocolatey.org/install.ps1',
    log_output              => true,
  }

  # Add the primary source (can be overridden via Hiera for air-gapped envs)
  chocolateysource { 'chocolatey':
    ensure   => present,
    location => $windows_baseline::chocolatey_source,
    priority => 100,
    require  => Class['chocolatey'],
  }

  # Security: require checksums on all packages
  chocolateyfeature { 'checksumFiles':
    ensure  => enabled,
    require => Class['chocolatey'],
  }

  # Disable unneeded telemetry
  chocolateyfeature { 'logEnvironmentValues':
    ensure  => disabled,
    require => Class['chocolatey'],
  }
}
```

### Step 3 — Classify the Windows node

On the Puppet Server, update `site.pp` to include the new module:

```puppet
node 'win01.example.com' {
  class { 'windows_baseline':
    server_packages => ['7zip', 'notepadplusplus', 'putty'],
  }
}
```

Apply on the Windows node and watch Chocolatey bootstrap:

```powershell
puppet agent --test
```

> Chocolatey installation takes 30–60 seconds on first run. Subsequent runs are instant (idempotent).

Verify Chocolatey is installed:

```powershell
choco --version
choco list --local-only
```

---

## Part 3 — Manage Packages with Chocolatey (20 min)

### Step 1 — Create the packages sub-class

Create `/etc/puppetlabs/code/environments/production/modules/windows_baseline/manifests/packages.pp`:

```puppet
# @summary Manages baseline and role-specific software packages.
class windows_baseline::packages {

  # Baseline packages present on ALL Windows nodes
  $baseline_packages = [
    '7zip',
    'notepadplusplus',
    'putty',
    'curl',
    'git',
  ]

  $baseline_packages.each |$pkg| {
    package { $pkg:
      ensure   => installed,
      provider => chocolatey,
      require  => Class['windows_baseline::chocolatey'],
    }
  }

  # Role-specific packages from class parameters (supplied by Hiera)
  $windows_baseline::developer_packages.each |$pkg| {
    package { "developer-${pkg}":
      name     => $pkg,
      ensure   => installed,
      provider => chocolatey,
      require  => Class['windows_baseline::chocolatey'],
    }
  }

  $windows_baseline::server_packages.each |$pkg| {
    package { "server-${pkg}":
      name     => $pkg,
      ensure   => installed,
      provider => chocolatey,
      require  => Class['windows_baseline::chocolatey'],
    }
  }

  # Remove legacy/insecure software
  $removed_packages = ['telnet', 'ftp']
  $removed_packages.each |$pkg| {
    package { "remove-${pkg}":
      name     => $pkg,
      ensure   => absent,
      provider => chocolatey,
    }
  }
}
```

### Step 2 — Drive package lists from Hiera

Create the module's default Hiera data file:

`/etc/puppetlabs/code/environments/production/modules/windows_baseline/data/common.yaml`:

```yaml
windows_baseline::developer_packages: []
windows_baseline::server_packages: []
windows_baseline::chocolatey_source: 'https://chocolatey.org/api/v2'
```

Create a role-specific data file (simulate via `hiera.yaml`):

Add to the production Hiera hierarchy (`/etc/puppetlabs/code/environments/production/hiera.yaml`):

```yaml
---
version: 5
hierarchy:
  - name: "Per-node data"
    path: "data/nodes/%{trusted.certname}.yaml"

  - name: "OS-family data"
    path: "data/os/%{facts.os.family}.yaml"

  - name: "Common data"
    path: "data/common.yaml"

defaults:
  data_hash: yaml_data
  datadir: ''
```

Create `/etc/puppetlabs/code/environments/production/data/nodes/win01.example.com.yaml`:

```yaml
windows_baseline::server_packages:
  - 'sysinternals'
  - 'winscp'
  - 'wireshark'
```

### Step 3 — Apply and verify

```powershell
puppet agent --test
```

Verify specific packages were installed:

```powershell
# List all Chocolatey-managed packages
choco list --local-only

# Find a specific package
choco list --local-only git

# Verify git is in PATH
git --version
```

---

## Part 4 — Registry Hardening (20 min)

### Step 1 — Create the registry_hardening sub-class

Create `/etc/puppetlabs/code/environments/production/modules/windows_baseline/manifests/registry_hardening.pp`:

```puppet
# @summary Applies registry-based security hardening settings.
#
# Implements key settings from CIS Windows Server benchmarks.
class windows_baseline::registry_hardening {

  # ── Disable SMBv1 ────────────────────────────────────────────────────────────
  # SMBv1 is the protocol exploited by WannaCry and NotPetya
  registry_value { 'HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters\SMB1':
    ensure => present,
    type   => dword,
    data   => 0,
  }

  # ── Disable autorun on all drive types ────────────────────────────────────────
  registry_key { 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer':
    ensure => present,
  }

  registry_value { 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer\NoDriveTypeAutoRun':
    ensure  => present,
    type    => dword,
    data    => 255,
    require => Registry_key['HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'],
  }

  # ── TLS 1.0 — disabled ────────────────────────────────────────────────────────
  registry_key { 'HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0':
    ensure => present,
  }

  registry_key { 'HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Server':
    ensure  => present,
    require => Registry_key['HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0'],
  }

  registry_value { 'HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Server\Enabled':
    ensure  => present,
    type    => dword,
    data    => 0,
    require => Registry_key['HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Server'],
  }

  # ── TLS 1.2 — enabled ─────────────────────────────────────────────────────────
  registry_key { 'HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2':
    ensure => present,
  }

  registry_key { 'HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server':
    ensure  => present,
    require => Registry_key['HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2'],
  }

  registry_value { 'HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server\Enabled':
    ensure  => present,
    type    => dword,
    data    => 1,
    require => Registry_key['HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server'],
  }

  # ── Puppet identification key ──────────────────────────────────────────────────
  # Record that this node is Puppet-managed and when it was last classified
  registry_key { 'HKLM\SOFTWARE\PuppetLabs\Management':
    ensure => present,
  }

  registry_value { 'HKLM\SOFTWARE\PuppetLabs\Management\Environment':
    ensure  => present,
    type    => string,
    data    => $environment,
    require => Registry_key['HKLM\SOFTWARE\PuppetLabs\Management'],
  }

  registry_value { 'HKLM\SOFTWARE\PuppetLabs\Management\CertName':
    ensure  => present,
    type    => string,
    data    => $trusted['certname'],
    require => Registry_key['HKLM\SOFTWARE\PuppetLabs\Management'],
  }
}
```

### Step 2 — Apply the changes

```powershell
puppet agent --test
```

### Step 3 — Verify the registry changes

```powershell
# Check SMBv1 disabled
Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' -Name SMB1
# SMB1 should be 0

# Check autorun disabled
Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' -Name NoDriveTypeAutoRun
# NoDriveTypeAutoRun should be 255

# Check Puppet management key
Get-ItemProperty -Path 'HKLM:\SOFTWARE\PuppetLabs\Management'
# Should show Environment and CertName values

# Test TLS 1.0 disabled
Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Server'
# Enabled should be 0

# Run Puppet again — verify it makes NO changes (idempotency)
puppet agent --test
# All lines should say "Applied catalog" with no "Notice:" change messages
```

---

## Part 5 — File Management with ACLs (20 min)

### Step 1 — Create a managed directory structure with permissions

Create `/etc/puppetlabs/code/environments/production/modules/windows_baseline/manifests/managed_dirs.pp`:

```puppet
# @summary Creates and manages application directories with NTFS ACLs.
class windows_baseline::managed_dirs {

  # Create the top-level directory
  file { 'C:/ProgramData/CompanyApp':
    ensure => directory,
  }

  # Subdirectories
  ['config', 'logs', 'data', 'temp'].each |$subdir| {
    file { "C:/ProgramData/CompanyApp/${subdir}":
      ensure  => directory,
      require => File['C:/ProgramData/CompanyApp'],
    }
  }

  # Manage a configuration file with strict permissions
  file { 'C:/ProgramData/CompanyApp/config/app.conf':
    ensure  => file,
    content => epp('windows_baseline/app.conf.epp', {
      node_name => $facts['networking']['hostname'],
      domain    => $facts['networking']['domain'],
    }),
    require => File['C:/ProgramData/CompanyApp/config'],
    notify  => Service['CompanyAppService'],
  }

  # ACL: config directory — Admins full, service account read-only, others denied
  acl { 'C:/ProgramData/CompanyApp/config':
    purge                      => true,
    inherit_parent_permissions => false,
    permissions                => [
      {
        identity => 'SYSTEM',
        rights   => ['full'],
      },
      {
        identity => 'Administrators',
        rights   => ['full'],
      },
      {
        identity => 'svcCompanyApp',
        rights   => ['read'],
        affects  => 'all',
      },
    ],
    require => File['C:/ProgramData/CompanyApp/config'],
  }

  # ACL: logs directory — service account can write, Admins can read
  acl { 'C:/ProgramData/CompanyApp/logs':
    purge                      => false,
    inherit_parent_permissions => true,
    permissions                => [
      {
        identity => 'svcCompanyApp',
        rights   => ['modify'],
        affects  => 'all',
      },
    ],
    require => File['C:/ProgramData/CompanyApp/logs'],
  }
}
```

### Step 2 — Create the EPP template for `app.conf`

Create `/etc/puppetlabs/code/environments/production/modules/windows_baseline/templates/app.conf.epp`:

```
<%- | String $node_name,
      String $domain,
| -%>
# Managed by Puppet — do not edit this file manually
# Changes will be overwritten on the next Puppet run
#
# Node: <%= $node_name %>
# Domain: <%= $domain %>

[general]
node_name = <%= $node_name %>
log_level = INFO
log_path  = C:/ProgramData/CompanyApp/logs

[database]
host     = db.example.com
port     = 5432
database = companyapp

[security]
tls_min_version = 1.2
```

### Step 3 — Create the service account and include the new sub-class

First, add a local service account class:

Create `/etc/puppetlabs/code/environments/production/modules/windows_baseline/manifests/service_accounts.pp`:

```puppet
# @summary Creates service accounts for application services.
class windows_baseline::service_accounts {

  user { 'svcCompanyApp':
    ensure     => present,
    comment    => 'Service account for CompanyApp — managed by Puppet',
    managehome => false,
    # Password retrieved from Hiera (eyaml-encrypted in production)
    # For this exercise, use a placeholder — NEVER hardcode passwords in real code
    password   => Sensitive(lookup('windows_baseline::svc_password', String, first, 'ChangeMe!1')),
  }

  group { 'CompanyAppUsers':
    ensure  => present,
    members => ['svcCompanyApp'],
    require => User['svcCompanyApp'],
  }
}
```

Add a placeholder stub for the CompanyApp service (so the `notify =>` in managed_dirs works):

```puppet
# /etc/puppetlabs/code/environments/production/modules/windows_baseline/manifests/services.pp
class windows_baseline::services {
  # This is a stub — in a real scenario the service would be installed
  # by a deployment pipeline before Puppet manages its config
  # We only manage the service if it actually exists
  if $facts.dig('service', 'CompanyAppService') {
    service { 'CompanyAppService':
      ensure => running,
      enable => true,
    }
  }
}
```

Update `init.pp` to include the new sub-classes:

```puppet
class windows_baseline (
  String        $chocolatey_source   = 'https://chocolatey.org/api/v2',
  Array[String] $developer_packages  = [],
  Array[String] $server_packages     = [],
) {
  unless $facts['kernel'] == 'windows' {
    fail("windows_baseline can only be applied to Windows nodes. Got: ${facts['kernel']}")
  }

  contain windows_baseline::chocolatey
  contain windows_baseline::registry_hardening
  contain windows_baseline::packages
  contain windows_baseline::env_vars
  contain windows_baseline::service_accounts
  contain windows_baseline::managed_dirs
  contain windows_baseline::services

  Class['windows_baseline::chocolatey']
    -> Class['windows_baseline::packages']
    -> Class['windows_baseline::service_accounts']
    -> Class['windows_baseline::managed_dirs']
    -> Class['windows_baseline::registry_hardening']
    -> Class['windows_baseline::env_vars']
    -> Class['windows_baseline::services']
}
```

### Step 4 — Apply and verify ACLs

```powershell
puppet agent --test
```

Verify the directory and file were created:

```powershell
# Check directory exists
Test-Path 'C:\ProgramData\CompanyApp\config'

# Read the config file
Get-Content 'C:\ProgramData\CompanyApp\config\app.conf'

# Verify ACLs on the config directory
Get-Acl -Path 'C:\ProgramData\CompanyApp\config' | Format-List

# The output should show:
# - SYSTEM: FullControl
# - Administrators: FullControl
# - svcCompanyApp: ReadAndExecute (if user exists)
```

---

## Part 6 — Environment Variables (10 min)

### Step 1 — Create the env_vars sub-class

Create `/etc/puppetlabs/code/environments/production/modules/windows_baseline/manifests/env_vars.pp`:

```puppet
# @summary Manages Windows system environment variables.
class windows_baseline::env_vars {

  # Set application home
  windows_env { 'COMPANY_APP_HOME':
    ensure    => present,
    value     => 'C:\Program Files\CompanyApp',
    mergemode => clobber,
  }

  # Add application bin to PATH
  windows_env { 'PATH=C:\Program Files\CompanyApp\bin':
    ensure    => present,
    mergemode => insert,
  }

  # Set log level (can be overridden per-node via Hiera)
  windows_env { 'COMPANY_APP_LOG_LEVEL':
    ensure    => present,
    value     => lookup('windows_baseline::log_level', String, first, 'INFO'),
    mergemode => clobber,
  }

  # Clean up old environment variable from previous version
  windows_env { 'OLD_APP_HOME':
    ensure => absent,
  }
}
```

### Step 2 — Apply and verify

```powershell
puppet agent --test
```

Verify environment variables:

```powershell
# System environment variables (requires a new PowerShell session to see updated PATH)
[System.Environment]::GetEnvironmentVariable('COMPANY_APP_HOME', 'Machine')
[System.Environment]::GetEnvironmentVariable('COMPANY_APP_LOG_LEVEL', 'Machine')

# Verify PATH contains the new entry
[System.Environment]::GetEnvironmentVariable('PATH', 'Machine') -split ';' |
    Where-Object { $_ -like '*CompanyApp*' }
```

---

## Part 7 — Idempotency Check and Change Simulation (10 min)

### Step 1 — Verify idempotency

Run Puppet twice and compare output:

```powershell
puppet agent --test

# Run again immediately
puppet agent --test
```

The second run should produce **no "Notice:" lines** about changes — only:
```
Info: Applying configuration version '...'
Notice: Applied catalog in X.XX seconds
```

### Step 2 — Simulate a configuration drift and observe Puppet correct it

Manually change the registry to simulate drift:

```powershell
# Break the SMBv1 setting manually
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' -Name SMB1 -Value 1
# Verify it changed
Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' -Name SMB1
# SMB1 is now 1 (wrong)
```

Now run Puppet in **noop** mode to preview the fix:

```powershell
puppet agent --test --noop
# Notice: /Registry_value[...SMB1]/data: current_value 1, should be 0 (noop)
```

Apply the fix:

```powershell
puppet agent --test
# Notice: /Registry_value[...SMB1]/data: changed 1 to 0
```

Verify Puppet corrected the drift:

```powershell
Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' -Name SMB1
# SMB1 is back to 0
```

> This is the core value proposition of Puppet: **automatic drift correction on every run**.

---

## Part 8 — Challenge Exercise

Extend `windows_baseline` with a `windows_baseline::firewall` class that manages Windows Firewall rules using the `exec` resource and PowerShell:

1. Allow inbound TCP port 443 (HTTPS)
2. Block inbound TCP port 23 (Telnet)
3. Allow inbound TCP port 3389 (RDP) only from the management subnet `10.0.0.0/24`

**Hints:**
- Use `New-NetFirewallRule` in PowerShell
- Use `unless` with `Get-NetFirewallRule` to check if the rule already exists
- The `provider => powershell` provider from `puppetlabs-powershell` is your friend

```puppet
exec { 'fw-allow-https':
  command  => 'New-NetFirewallRule -DisplayName "Allow HTTPS" -Direction Inbound -Protocol TCP -LocalPort 443 -Action Allow',
  provider => powershell,
  unless   => 'if (Get-NetFirewallRule -DisplayName "Allow HTTPS" -ErrorAction SilentlyContinue) { exit 0 } else { exit 1 }',
}
```

---

## Summary

You have:
1. Built a `windows_baseline` module with proper sub-class decomposition
2. Bootstrapped and configured Chocolatey with security features
3. Managed software packages with version pinning and role-specific lists
4. Applied registry-based security hardening (SMBv1, TLS, autorun)
5. Created directories with fine-grained NTFS ACLs using `puppetlabs-acl`
6. Generated a configuration file from an EPP template
7. Managed system environment variables with `puppet-windows_env`
8. Verified idempotency and observed automatic drift correction

**Continue to Exercise 3** to build a truly cross-platform module and integrate with DSC for IIS management.
