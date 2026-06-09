---
marp: true
paginate: true
---

# Puppet Base Course

## Day 4

**Windows with Puppet**

---

## Day 4 — Agenda

### Part 1 — Windows and Puppet: The Big Picture
- Why manage Windows with Puppet?
- Key architectural differences from Linux
- What the Windows AIO agent contains
- Directory layout on Windows

### Part 2 — Installing and Bootstrapping the Windows Agent
- MSI installer and silent deployment
- Connecting to the Puppet Server
- Certificate signing for Windows nodes
- Triggering the first catalog run

---

### Part 3 — Core Windows Resources
- `package` — Windows providers (chocolatey, windows, msi, msu)
- `file` — Windows paths, ACLs, line endings
- `service` — Service Control Manager integration
- `user` and `group` — Local accounts
- `registry_key` and `registry_value`
- `exec` — Running PowerShell from Puppet

### Part 4 — Chocolatey Package Management
- What Chocolatey is and why it matters
- Installing Chocolatey via Puppet
- Managing packages, versions, and sources
- The `puppetlabs-chocolatey` module deep dive

---

### Part 5 — Windows-Specific Puppet Modules
- `puppetlabs-acl` — Fine-grained NTFS permissions
- `puppetlabs-registry` — Registry management
- `puppet-windows_env` — Environment variables
- `puppetlabs-iis` — IIS web server management
- `puppetlabs-sqlserver` — SQL Server management

### Part 6 — DSC Integration
- What is Desired State Configuration (DSC)?
- The Puppet DSC bridge
- Auto-generated `dsc_*` resource types
- When to use DSC vs. native Puppet resources

---

### Part 7 — Facts on Windows
- Windows-specific structured facts
- PowerShell-based custom facts
- Using Windows facts for conditional manifests

### Part 8 — Templates and Files on Windows
- File path handling — forward vs. backward slashes
- Line endings and encoding (CRLF)
- EPP templates for Windows configuration files

### Part 9 — Cross-Platform Modules
- Structuring modules that work on Linux AND Windows
- `$facts['kernel']` and `$facts['os']['family']`
- Platform-specific Hiera data
- Module metadata for Windows support

### Part 10 — Testing Windows Puppet Code
- PDK on Windows
- rspec-puppet for cross-platform modules
- Acceptance testing with Litmus

---

<!-- _class: lead -->

# Part 1 — Windows and Puppet: The Big Picture

---

## Why Manage Windows with Puppet?

Windows estates have the same problems as Linux — and often more:

| Problem | Without Puppet | With Puppet |
|---|---|---|
| Software inventory | Unknown — audit is a manual spreadsheet | `puppet resource package` — instant truth |
| Group Policy limits | GPO can only reach domain-joined machines | Puppet works standalone or in a workgroup |
| Security baseline | Enforced manually, drifts between reboots | Puppet re-enforces every 30 minutes |
| Hundreds of registry keys | Script + hope + prayer | Declared resources, version-controlled |
| IIS config management | ClickOps or undocumented PowerShell | Puppet manifest, peer-reviewed in Git |
| Secret sprawl | Passwords in spreadsheets | Hiera + eyaml, encrypted at rest |

> Mixed estates (Linux + Windows) are the norm in enterprises. Puppet manages both from a single control repository.

---

## What's Different on Windows?

Puppet's architecture is identical — same server, same catalog, same run cycle. The differences are in how resources are **implemented**:

| Concept | Linux | Windows |
|---|---|---|
| Package manager | apt, yum, dnf | Chocolatey, MSI, MSU |
| File paths | `/etc/nginx/nginx.conf` | `C:\ProgramData\nginx\nginx.conf` |
| Service manager | systemd | Service Control Manager (SCM) |
| Users / groups | `/etc/passwd`, `/etc/group` | Local Security Authority (LSA) |
| Permissions | POSIX rwxrwxrwx | NTFS ACL / DACL / SACL |
| Config store | Files in /etc | Files + Windows Registry |
| Scripting engine | bash / sh | PowerShell |
| AIO install path | `/opt/puppetlabs/` | `C:\Program Files\Puppet Labs\Puppet\` |
| Data path | `/etc/puppetlabs/` | `C:\ProgramData\PuppetLabs\` |

---

## Puppet Agent on Windows — Architecture

![w:900](../assets/windows-agent-architecture.svg)

---

## Key Points: The Windows AIO Package

The `puppet-agent` MSI installs everything Puppet needs:

```
C:\Program Files\Puppet Labs\Puppet\
├── bin\
│   ├── puppet.bat        ← wrapper for the puppet binary
│   ├── facter.bat        ← fact collection
│   └── ruby.bat          ← bundled Ruby runtime
├── puppet\               ← Puppet Ruby code
├── facter\               ← Facter Ruby code
└── sys\ruby\             ← Bundled Ruby + gems
```

Configuration and data live separately:

```
C:\ProgramData\PuppetLabs\
├── puppet\
│   ├── etc\
│   │   ├── puppet.conf     ← main config file
│   │   └── ssl\            ← certificates
│   └── cache\              ← catalog cache, run reports
└── facter\
    └── facts.d\            ← external facts directory
```

> **Security note:** The `puppet-agent` service runs as `SYSTEM` by default. Use a dedicated service account in production — configure via `sc.exe` or the `windows_service_account` module.

---

## The Windows Provider Stack

![w:900](../assets/windows-provider-stack.svg)

---

<!-- _class: lead -->

# Part 2 — Installing and Bootstrapping the Windows Agent

---

## Installing the Puppet Agent on Windows

### Method 1 — Interactive MSI

1. Download from: `https://downloads.puppet.com/windows/puppet8/puppet-agent-x64-latest.msi`
2. Run the MSI wizard
3. Enter the Puppet Server hostname when prompted
4. The wizard configures `puppet.conf` and starts the service

### Method 2 — Silent Install (recommended for automation)

```powershell
# Download the MSI
$url = 'https://downloads.puppet.com/windows/puppet8/puppet-agent-x64-latest.msi'
Invoke-WebRequest -Uri $url -OutFile 'puppet-agent.msi'

# Silent install — specify the server hostname
msiexec /qn /norestart /i puppet-agent.msi ^
  PUPPET_SERVER=puppet.example.com ^
  PUPPET_AGENT_CERTNAME=win01.example.com ^
  PUPPET_AGENT_ENVIRONMENT=production

# Or with PowerShell Start-Process for better control
Start-Process msiexec -ArgumentList @(
  '/qn', '/norestart', '/i', 'puppet-agent.msi',
  'PUPPET_SERVER=puppet.example.com',
  'PUPPET_AGENT_CERTNAME=win01.example.com'
) -Wait -NoNewWindow
```

---

## MSI Install Properties

All MSI properties can be set during silent install:

| Property | Default | Description |
|---|---|---|
| `PUPPET_SERVER` | `puppet` | Puppet Server hostname |
| `PUPPET_AGENT_CERTNAME` | FQDN | Agent certificate name (should match FQDN) |
| `PUPPET_AGENT_ENVIRONMENT` | `production` | Puppet environment |
| `PUPPET_MASTER_PORT` | `8140` | Server port |
| `PUPPET_AGENT_STARTUP_MODE` | `Automatic` | Windows service startup type |
| `PUPPET_AGENT_ACCOUNT_USER` | — | Service account user |
| `PUPPET_AGENT_ACCOUNT_PASSWORD` | — | Service account password |
| `PUPPET_AGENT_ACCOUNT_DOMAIN` | — | Service account domain |

---

## Configuring the Agent After Install

Edit `C:\ProgramData\PuppetLabs\puppet\etc\puppet.conf`:

```ini
[main]
server      = puppet.example.com
certname    = win01.example.com
environment = production

[agent]
runinterval = 1800
waitforcert = 120
```

> `waitforcert` tells the agent to keep trying for up to 120 seconds while waiting for its certificate to be signed. Very useful during automated provisioning.

Verify the configuration:

```powershell
# Open a PowerShell prompt as Administrator
puppet config print server
puppet config print certname
puppet config print environment
```

---

## Certificate Signing for Windows Nodes

The process is **identical** to Linux:

### On the Windows agent — submit the CSR

```powershell
# Run as Administrator
puppet agent --test
# Agent will output: "Exiting; no certificate found and waitforcert is disabled"
# or wait up to waitforcert seconds if set
```

### On the Puppet Server — sign the certificate

```bash
# List pending certificate requests
puppetserver ca list

# Sign a specific node
puppetserver ca sign --certname win01.example.com

# Sign all pending requests (use with care)
puppetserver ca sign --all
```

### Back on the Windows agent — trigger the first run

```powershell
puppet agent --test
```

---

## Verifying the First Run

A successful first run looks like this:

```
Info: Using environment 'production'
Info: Retrieving pluginfacts
Info: Retrieving plugin
Info: Caching catalog for win01.example.com
Info: Applying configuration version '1234567890'
Notice: Applied catalog in 3.14 seconds
```

Key checks after the first run:

```powershell
# Check agent service status
Get-Service puppet

# Check the last run report
puppet agent --test --summarize

# View the run log
Get-Content "C:\ProgramData\PuppetLabs\puppet\cache\state\last_run_summary.yaml"

# Check for errors in the run report
puppet agent --test 2>&1 | Select-String "Error|Warning|Notice"
```

---

## Starting the Agent Service

```powershell
# Start and configure the service
Start-Service puppet
Set-Service puppet -StartupType Automatic

# Trigger an immediate run without waiting for the interval
& "C:\Program Files\Puppet Labs\Puppet\bin\puppet.bat" agent --test

# Run in no-op (dry-run) mode — see what WOULD change
& "C:\Program Files\Puppet Labs\Puppet\bin\puppet.bat" agent --test --noop
```

Adding Puppet binaries to `PATH` (done by the MSI, but verify):

```powershell
# Verify Puppet is on PATH
puppet --version

# If not, add manually (restart shell after)
$pp = 'C:\Program Files\Puppet Labs\Puppet\bin'
[Environment]::SetEnvironmentVariable(
  'PATH',
  "$env:PATH;$pp",
  'Machine'
)
```

---

<!-- _class: lead -->

# Part 3 — Core Windows Resources

---

## `package` — The Windows Package Resource

The `package` resource on Windows supports multiple providers:

```puppet
# Install via Chocolatey (recommended — see Part 4)
package { 'googlechrome':
  ensure   => installed,
  provider => chocolatey,
}

# Install from a specific MSI file (served by Puppet file server)
package { 'MyApplication':
  ensure          => installed,
  provider        => windows,
  source          => '\\\\fileserver\share\MyApp-2.0.msi',
  install_options => ['/quiet', '/norestart',
                      { 'INSTALLDIR' => 'C:\MyApp' }],
}

# Windows Update packages (.msu patches)
package { 'KB5028185':
  ensure   => installed,
  provider => msu,
  source   => 'C:\Updates\windows10.0-kb5028185-x64.msu',
}
```

---

## `package` — `install_options` and `uninstall_options`

Both `install_options` and `uninstall_options` accept an **array** of strings and hashes:

```puppet
package { 'MyApp':
  ensure          => installed,
  provider        => windows,
  source          => puppet:///modules/myapp/MyApp-2.0.msi,
  install_options => [
    '/quiet',
    '/norestart',
    { 'ADDLOCAL'    => 'FeatureA,FeatureB' },
    { 'INSTALLDIR'  => 'C:\\Program Files\\MyApp' },
    { 'TRANSFORMS'  => 'C:\\Transforms\\corporate.mst' },
  ],
  uninstall_options => ['/quiet', '/norestart'],
}
```

> **Strings** become command-line flags. **Hashes** become `KEY=VALUE` pairs. This maps directly to `msiexec` command line syntax.

---

## `file` — Windows File Paths

Puppet accepts **forward slashes** on Windows — always prefer them to avoid escaping:

```puppet
# GOOD — forward slashes work everywhere
file { 'C:/ProgramData/MyApp/config.ini':
  ensure  => file,
  content => epp('myapp/config.ini.epp'),
}

# ALSO VALID — backslashes must be doubled (escaped)
file { 'C:\\ProgramData\\MyApp\\config.ini':
  ensure  => file,
  content => 'setting=value',
}

# Create a directory
file { 'C:/ProgramData/MyApp':
  ensure => directory,
}

# Manage a directory tree recursively
file { 'C:/ProgramData/MyApp/conf.d':
  ensure  => directory,
  recurse => true,
  purge   => true,
  source  => 'puppet:///modules/myapp/conf.d',
}
```

---

## `file` — Windows-Specific Attributes

```puppet
file { 'C:/ProgramData/MyApp/config.ini':
  ensure  => file,
  content => epp('myapp/config.ini.epp'),
  owner   => 'Administrators',   # Windows group or user name
  group   => 'SYSTEM',
  mode    => '0640',             # POSIX-style mode (converted to ACL)
}
```

> **Important:** On Windows, `owner`, `group`, and `mode` are mapped to Windows ACL entries by the `file` resource. For **fine-grained ACL control** (multiple ACEs, inheritance flags, deny rules), use the `puppetlabs-acl` module (covered in Part 5).

### Line endings and encoding

```puppet
file { 'C:/MyApp/config.txt':
  ensure   => file,
  content  => "key=value\r\n",   # explicit CRLF
  # Or use an EPP template — Puppet preserves template line endings
}
```

> Puppet does **not** automatically convert LF to CRLF. If your config files require Windows line endings, handle this in your EPP template or content string.

---

## `service` — Windows Service Control Manager

```puppet
# Ensure a service is running and starts automatically
service { 'W3SVC':                  # IIS World Wide Web service
  ensure => running,
  enable => true,
}

# Stop and disable a service (e.g., disable SMBv1)
service { 'mrxsmb10':
  ensure => stopped,
  enable => false,
}

# Manage a custom-installed service
service { 'MyAppService':
  ensure    => running,
  enable    => true,
  subscribe => File['C:/ProgramData/MyApp/config.ini'],
}
```

Windows service `enable` values map to SCM startup types:

| Puppet `enable` | SCM Startup Type |
|---|---|
| `true` | Automatic |
| `false` | Disabled |
| `manual` | Manual |
| `delayed` | Automatic (Delayed Start) |

---

## `user` — Local Windows Users

```puppet
user { 'svcaccount':
  ensure   => present,
  password => Sensitive('Str0ng!P@ssw0rd'),   # use Sensitive() — never plain string
  comment  => 'Service account for MyApp',
  groups   => ['Administrators'],
  managehome => false,
}

# Remove a user
user { 'olduser':
  ensure => absent,
}
```

> **Security:** Wrap passwords in `Sensitive()` to prevent them appearing in reports and logs. Better still, retrieve them from Hiera with eyaml encryption.

```puppet
# Retrieve password from Hiera (encrypted with eyaml)
$svc_password = lookup('myapp::svc_password')

user { 'svcaccount':
  ensure   => present,
  password => Sensitive($svc_password),
}
```

---

## `group` — Local Windows Groups

```puppet
# Create a local group
group { 'MyAppAdmins':
  ensure  => present,
  members => ['svcaccount', 'DOMAIN\AppTeam'],
}

# Add members to the built-in Administrators group
group { 'Administrators':
  ensure  => present,
  members => ['DOMAIN\AppTeam'],
}
```

> **Domain accounts:** Use `DOMAIN\username` format. For Azure AD / Entra ID joined machines, use `AzureAD\username`.

---

## `registry_key` and `registry_value`

These are provided by the **`puppetlabs-registry`** module:

```puppet
# Ensure a registry key exists
registry_key { 'HKLM\SOFTWARE\MyApp':
  ensure => present,
}

# Set a registry value
registry_value { 'HKLM\SOFTWARE\MyApp\InstallDir':
  ensure => present,
  type   => string,
  data   => 'C:\Program Files\MyApp',
}

# REG_DWORD value
registry_value { 'HKLM\SOFTWARE\MyApp\MaxConnections':
  ensure => present,
  type   => dword,
  data   => 10,
}

# REG_MULTI_SZ value (multi-line string)
registry_value { 'HKLM\SOFTWARE\MyApp\AllowedHosts':
  ensure => present,
  type   => array,
  data   => ['server1.example.com', 'server2.example.com'],
}
```

---

## Registry Value Types

| Puppet `type` | Windows Registry Type | Example data |
|---|---|---|
| `string` | REG_SZ | `'hello world'` |
| `expand` | REG_EXPAND_SZ | `'%WINDIR%\system32'` |
| `array` | REG_MULTI_SZ | `['a', 'b', 'c']` |
| `dword` | REG_DWORD | `42` |
| `qword` | REG_QWORD | `9999999999` |
| `binary` | REG_BINARY | `'DEADBEEF'` (hex string) |

```puppet
# REG_EXPAND_SZ — environment variable expansion
registry_value { 'HKLM\SOFTWARE\MyApp\LogPath':
  ensure => present,
  type   => expand,
  data   => '%TEMP%\MyApp\logs',
}

# Remove a registry value
registry_value { 'HKLM\SOFTWARE\MyApp\OldSetting':
  ensure => absent,
}
```

---

## `exec` — Running PowerShell from Puppet

```puppet
# Run a PowerShell command
exec { 'configure-tls':
  command  => 'powershell.exe',
  arguments => [
    '-ExecutionPolicy', 'Bypass',
    '-Command',
    '[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12',
  ],
  provider => powershell,
  unless   => 'if ([Net.ServicePointManager]::SecurityProtocol -match "Tls12") { exit 0 } else { exit 1 }',
}
```

Using the **`powershell` provider** (from `puppetlabs-powershell` module):

```puppet
exec { 'set-timezone':
  command  => 'Set-TimeZone -Name "Central European Standard Time"',
  provider => powershell,
  unless   => 'if ((Get-TimeZone).Id -eq "Central European Standard Time") { exit 0 } else { exit 1 }',
}
```

> **Always provide `unless`, `onlyif`, or `creates`** — without a guard, `exec` runs on every Puppet run and breaks idempotency.

---

## `exec` — The `powershell` Provider Deep Dive

```puppet
# Multi-line PowerShell with here-string
exec { 'configure-winrm':
  command  => @("PS"/L),
    $listener = Get-WSManInstance -ResourceURI winrm/config/listener -SelectorSet @{Transport="HTTPS";Address="*"} -ErrorAction SilentlyContinue
    if (-not $listener) {
      New-WSManInstance -ResourceURI winrm/config/listener -SelectorSet @{Transport="HTTPS";Address="*"} -ValueSet @{CertificateThumbprint="AUTO"}
    }
    | PS
  provider => powershell,
  unless   => 'if (Get-WSManInstance winrm/config/listener -SelectorSet @{Transport="HTTPS";Address="*"} -ErrorAction SilentlyContinue) { exit 0 } else { exit 1 }',
}
```

> The `@("PS"/L)` heredoc with the `L` flag strips leading whitespace — clean and readable.

---

<!-- _class: lead -->

# Part 4 — Chocolatey Package Management

---

## What is Chocolatey?

Chocolatey is the **de facto standard package manager for Windows** — it's `apt`/`yum` for Windows.

- Wraps installation logic in **NuGet packages** (`.nupkg` files)
- Community repository at `chocolatey.org` with **9000+ packages**
- Commercial editions (Chocolatey Business) add internalization, GUI, and enhanced security
- Integrates naturally with Puppet through the `puppetlabs-chocolatey` module

```
Without Chocolatey:              With Chocolatey:
Manual download + MSI wizard     choco install git --yes
No version management            choco upgrade all --yes
No central inventory             choco list --local-only
No unattended install            choco install vscode --yes --no-progress
```

---

## The Chocolatey Flow

![w:900](../assets/chocolatey-flow.svg)

---

## Step 1 — Bootstrap Chocolatey via Puppet

Use the `puppetlabs-chocolatey` module to manage Chocolatey itself:

```bash
# On the Puppet Server — add to Puppetfile
puppet module install puppetlabs-chocolatey
```

```puppet
# In your Windows profile or role manifest
include chocolatey

# Or with explicit parameters
class { 'chocolatey':
  chocolatey_download_url => 'https://chocolatey.org/install.ps1',
  use_7zip                => false,
  log_output              => true,
}
```

The `chocolatey` class will:
1. Download and run the Chocolatey install script
2. Add `choco.exe` to `PATH`
3. Configure Chocolatey's settings
4. Manage the Chocolatey service (if using Business edition)

---

## Step 2 — Manage Packages with Chocolatey

```puppet
# Install the latest version
package { 'googlechrome':
  ensure   => installed,
  provider => chocolatey,
}

# Pin to an exact version
package { 'git':
  ensure   => '2.43.0',
  provider => chocolatey,
}

# Always upgrade to the latest
package { 'vlc':
  ensure   => latest,
  provider => chocolatey,
}

# Install with package-specific options
package { 'vscode':
  ensure          => installed,
  provider        => chocolatey,
  install_options => ['--params', '"/NoDesktopIcon /NoQuicklaunch"'],
}

# Remove a package
package { 'telnet':
  ensure   => absent,
  provider => chocolatey,
}
```

---

## Managing Multiple Packages

```puppet
# Use an array — clean, DRY
$developer_tools = [
  'git',
  'vscode',
  'googlechrome',
  'firefox',
  'notepadplusplus',
  'putty',
  '7zip',
  'curl',
  'jq',
]

$developer_tools.each |$pkg| {
  package { $pkg:
    ensure   => installed,
    provider => chocolatey,
    require  => Class['chocolatey'],
  }
}
```

Or drive from Hiera data:

```yaml
# data/roles/developer.yaml
profile::windows::packages:
  googlechrome: 'latest'
  git: '2.43.0'
  vscode: 'installed'
  notepadplusplus: 'installed'
```

---

## Configuring Chocolatey Sources

```puppet
# Add an internal Nexus/Artifactory source
chocolateysource { 'corporate':
  ensure   => present,
  location => 'https://nexus.example.com/repository/chocolatey/',
  priority => 1,                    # lower number = higher priority
  user     => 'choco_reader',
  password => Sensitive($choco_password),
}

# Disable the public community feed (air-gapped environments)
chocolateysource { 'chocolatey':
  ensure   => present,
  enabled  => false,
}

# Add a local network share as a source
chocolateysource { 'local-packages':
  ensure   => present,
  location => '\\\\fileserver\chocolatey-packages',
  priority => 0,
}
```

---

## Chocolatey Configuration Settings

```puppet
# Set the cache location
chocolateyconfig { 'cacheLocation':
  ensure => present,
  value  => 'C:\ProgramData\chocolatey\cache',
}

# Proxy settings (corporate environments)
chocolateyconfig { 'proxy':
  ensure => present,
  value  => 'http://proxy.example.com:8080',
}

chocolateyconfig { 'proxyBypassList':
  ensure => present,
  value  => 'internal.example.com,*.corp.example.com',
}

# Require checksums on all packages (security best practice)
chocolateyfeature { 'checksumFiles':
  ensure => enabled,
}

# Disable telemetry
chocolateyfeature { 'useFipsCompliantChecksums':
  ensure => enabled,
}
```

---

<!-- _class: lead -->

# Part 5 — Windows-Specific Puppet Modules

---

## `puppetlabs-acl` — Fine-Grained NTFS Permissions

The built-in `file` resource maps `mode` to a simple ACL. For production Windows infrastructure you need **`puppetlabs-acl`**:

```bash
puppet module install puppetlabs-acl
```

```puppet
acl { 'C:/ProgramData/MyApp':
  purge       => false,              # keep existing ACEs we don't manage
  permissions => [
    {
      identity => 'SYSTEM',
      rights   => ['full'],
    },
    {
      identity    => 'Administrators',
      rights      => ['full'],
      affects     => 'all',          # this object + all descendants
    },
    {
      identity => 'MyAppService',
      rights   => ['read', 'execute'],
      affects  => 'self_only',       # only the directory itself
    },
    {
      identity => 'Everyone',
      rights   => ['read'],
      type     => 'deny',            # explicit deny entry
    },
  ],
}
```

---

## `puppetlabs-acl` — Advanced Usage

```puppet
# Manage an ACL with inheritance settings
acl { 'C:/Secure':
  inherit_parent_permissions => false,   # break inheritance
  purge                      => true,    # remove all unmanaged ACEs
  permissions                => [
    {
      identity => 'Administrators',
      rights   => ['full'],
    },
    {
      identity     => 'CREATOR OWNER',
      rights       => ['full'],
      child_types  => 'objects',         # apply to child objects
      affects      => 'children_only',
    },
  ],
}

# ACL rights shortcuts
# 'full'          → FullControl
# 'modify'        → Modify (read+write+execute+delete)
# 'write'         → Write
# 'read'          → Read & Execute
# 'execute'       → ReadAndExecute
# ['read','write']→ custom combination
```

---

## `puppetlabs-registry` — Registry Management

```bash
puppet module install puppetlabs-registry
```

```puppet
# Disable autorun via the registry
registry_key { 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer':
  ensure => present,
}

registry_value { 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer\NoDriveTypeAutoRun':
  ensure => present,
  type   => dword,
  data   => 255,    # disable autorun on all drive types
}

# Configure IE Enhanced Security (useful for server roles)
registry_value { 'HKLM\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}\IsInstalled':
  ensure => present,
  type   => dword,
  data   => 0,      # 0 = disabled for Administrators
}

# Environment variable in registry
registry_value { 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment\MY_APP_HOME':
  ensure => present,
  type   => expand,
  data   => 'C:\Program Files\MyApp',
}
```

---

## `puppet-windows_env` — Environment Variables

For managing Windows environment variables more cleanly than registry manipulation:

```bash
puppet module install puppet-windows_env
```

```puppet
# Set a system-wide environment variable
windows_env { 'JAVA_HOME':
  ensure    => present,
  value     => 'C:\Program Files\Java\jdk-17',
  mergemode => clobber,   # replace existing value
}

# Add to PATH — mergemode => insert adds without removing existing entries
windows_env { 'PATH=C:\MyApp\bin':
  ensure    => present,
  mergemode => insert,
}

# Remove from PATH
windows_env { 'PATH=C:\OldApp\bin':
  ensure => absent,
}

# User-level environment variable
windows_env { 'EDITOR':
  ensure    => present,
  value     => 'notepad',
  user      => 'Developer',
}
```

---

## `puppetlabs-iis` — IIS Management

```bash
puppet module install puppetlabs-iis
```

```puppet
# Ensure IIS is installed (uses DSC internally)
include iis

# Create an application pool
iis_application_pool { 'MyAppPool':
  ensure                => present,
  state                 => started,
  managed_runtime_version => 'v4.0',
  managed_pipeline_mode => 'Integrated',
  identity_type         => 'ApplicationPoolIdentity',
  start_mode            => 'AlwaysRunning',
}

# Create a website
iis_site { 'MyApp':
  ensure          => present,
  physpath        => 'C:\inetpub\MyApp',
  bindings        => [
    { protocol => 'http',  port => 80,  hostheader => 'myapp.example.com' },
    { protocol => 'https', port => 443, hostheader => 'myapp.example.com',
      certificatestorename => 'MY', certificatehash => $cert_thumbprint },
  ],
  applicationpool => 'MyAppPool',
  logformat       => 'W3C',
  logpath         => 'C:\inetpub\logs\LogFiles',
}
```

---

## `puppetlabs-iis` — Virtual Directories and Applications

```puppet
# Create an IIS application under a site
iis_application { 'api':
  ensure          => present,
  sitename        => 'MyApp',
  physpath        => 'C:\inetpub\MyApp\api',
  applicationpool => 'MyAppPool',
}

# Virtual directory
iis_virtual_directory { 'assets':
  ensure   => present,
  sitename => 'MyApp',
  physpath => 'D:\StaticAssets',
}

# Configure application pool recycling
iis_application_pool { 'MyAppPool':
  ensure                   => present,
  periodic_restart_time    => '02:00:00',   # recycle at 2am
  idle_timeout             => '00:20:00',
  max_processes            => 1,
  rapid_fail_protection    => true,
}
```

---

<!-- _class: lead -->

# Part 6 — DSC Integration

---

## What is DSC?

**Desired State Configuration (DSC)** is Microsoft's own declarative configuration system for Windows, built into PowerShell.

```
┌─────────────────────────────────────────────────────────┐
│  DSC at a glance                                        │
│                                                         │
│  • Declarative, like Puppet                             │
│  • Resources describe desired state                     │
│  • LCM (Local Configuration Manager) enforces state     │
│  • 300+ resources in the PSGallery for IIS, SQL, AD, …  │
│  • Microsoft maintains core resources                   │
│                                                         │
│  The problem: DSC alone lacks Puppet's ecosystem        │
│  • No certificate-based multi-node management           │
│  • No Hiera-equivalent external data                    │
│  • No Forge equivalent for code sharing                 │
│  • No built-in reporting / PuppetDB equivalent          │
│                                                         │
│  The solution: Use DSC resources FROM Puppet            │
└─────────────────────────────────────────────────────────┘
```

---

## The Puppet DSC Bridge

![w:900](../assets/dsc-bridge.svg)

---

## Installing DSC Bridge Modules

Puppet auto-generates Forge modules from PSGallery DSC resources:

```bash
# Install on the Puppet Server
puppet module install puppetlabs-dsc_lite        # generic DSC bridge
puppet module install puppet-windowsfeature      # Windows roles/features
puppet module install puppet-iis                 # IIS via DSC
puppet module install puppet-sqlserver_dsc        # SQL Server via DSC
puppet module install puppet-auditpol             # Audit policy
```

Or list them in `Puppetfile`:

```ruby
# Puppetfile
mod 'puppetlabs-dsc_lite',     '1.4.0'
mod 'puppet-windowsfeature',   '3.0.1'
mod 'puppet-iis',              '9.0.2'
mod 'puppet-sqlserver_dsc',    '3.0.1'
```

---

## Using `dsc_lite` — The Generic Bridge

`dsc_lite` gives you access to **any** DSC resource, even if there is no auto-generated module:

```puppet
# Install a Windows Feature using DSC
dsc { 'install-web-server':
  resource_name => 'WindowsFeature',
  module        => 'PSDesiredStateConfiguration',
  properties    => {
    ensure => 'Present',
    name   => 'Web-Server',
  },
}

# Configure IIS Application Pool via DSC
dsc { 'apppool-myapp':
  resource_name => 'xWebAppPool',
  module        => { name => 'xWebAdministration', version => '3.3.0' },
  properties    => {
    ensure                => 'Present',
    name                  => 'MyApp',
    managedRuntimeVersion => 'v4.0',
    state                 => 'Started',
  },
}
```

---

## Using Auto-Generated `dsc_*` Resources

Auto-generated modules produce typed resource types with validation:

```puppet
# Install Windows Feature using puppet-windowsfeature
dsc_windowsfeature { 'Web-Server':
  dsc_ensure => 'Present',
  dsc_name   => 'Web-Server',
}

# Install multiple Windows features
['Web-Server', 'Web-Asp-Net45', 'Web-Mgmt-Console'].each |$feature| {
  dsc_windowsfeature { $feature:
    dsc_ensure => 'Present',
    dsc_name   => $feature,
  }
}

# Configure a Windows Firewall rule via DSC
dsc_firewall { 'allow-https':
  dsc_ensure    => 'Present',
  dsc_name      => 'Allow HTTPS Inbound',
  dsc_localport => ['443'],
  dsc_protocol  => 'TCP',
  dsc_direction => 'Inbound',
  dsc_action    => 'Allow',
  dsc_enabled   => 'True',
}
```

---

## DSC for SQL Server

The `puppet-sqlserver_dsc` module wraps the `SqlServerDsc` PowerShell module:

```puppet
# Install SQL Server instance via DSC
dsc_sqlsetup { 'MSSQLSERVER':
  dsc_instancename    => 'MSSQLSERVER',
  dsc_features        => 'SQLENGINE,SSMS',
  dsc_sourcepath      => '\\\\fileserver\SQLServer2022',
  dsc_sapwd           => Sensitive('Str0ng!SAPassword'),
  dsc_securitymode    => 'SQL',
  dsc_sqluserdbdir    => 'D:\SQLData',
  dsc_sqluserlogdir   => 'E:\SQLLogs',
  dsc_sqltempdbdir    => 'F:\SQLTempDB',
  dsc_sqlsysadminaccounts => ['Administrators', 'sa'],
}

# Create a SQL database
dsc_sqldatabase { 'AppDB':
  dsc_instancename => 'MSSQLSERVER',
  dsc_name         => 'AppDB',
  dsc_ensure       => 'Present',
}
```

---

## When to Use DSC vs. Native Puppet Resources

| Use Case | Recommendation |
|---|---|
| Files, users, groups, basic services | Native Puppet — simpler, faster |
| Windows Features (roles) | `dsc_windowsfeature` or `puppet-windowsfeature` |
| IIS configuration | `puppetlabs-iis` (DSC-based) or `dsc_lite` |
| SQL Server | `puppet-sqlserver_dsc` |
| Active Directory management | DSC `ActiveDirectoryDsc` module |
| Registry keys | `puppetlabs-registry` (native Ruby provider) |
| NTFS permissions | `puppetlabs-acl` (native Ruby provider) |
| Anything in PSGallery | `dsc_lite` as a fallback |
| Cross-platform resources | Native Puppet only — DSC is Windows-only |

> **Rule of thumb:** Start with native Puppet resources. Reach for DSC when you need Windows-specific functionality that has no native Puppet equivalent, or when the DSC resource is maintained by Microsoft and you want its validation logic.

---

<!-- _class: lead -->

# Part 7 — Facts on Windows

---

## Windows-Specific Facts

Facter on Windows collects a rich set of Windows-specific facts:

```powershell
# Run Facter on the Windows node
facter

# Key facts available on Windows
facter os                          # OS name, family, release
facter os.windows                  # Windows edition, installation_type
facter kernel                      # 'windows'
facter kernelversion               # NT kernel version (e.g., 10.0.19041)
facter processors                  # count, speed, models
facter memory                      # total, available, used
facter networking                  # IP addresses, interfaces, domain
facter identity                    # username, uid, privileged
facter virtual                     # virtualisation type
facter disks                       # disk sizes and types
```

```powershell
# Query a specific structured fact
facter os.windows.edition_id       # e.g., "ServerStandard"
facter os.windows.installation_type  # "Server" or "Client"
facter os.windows.product_name     # "Windows Server 2022 Standard"
facter os.release.full             # e.g., "10.0.20348"
```

---

## Using Windows Facts in Manifests

```puppet
# Branch on Windows edition
if $facts['os']['windows']['installation_type'] == 'Server' {
  include role::windows_server
} else {
  include role::windows_workstation
}

# Select correct service name based on Windows version
$iis_service = $facts['os']['windows']['product_name'] ? {
  /Server 2012/ => 'W3SVC',
  /Server 2016/ => 'W3SVC',
  /Server 2019/ => 'W3SVC',
  /Server 2022/ => 'W3SVC',
  default       => 'W3SVC',
}

# Act on whether running in a virtual machine
if $facts['virtual'] in ['vmware', 'hyperv', 'virtualbox'] {
  include profile::vm_guest_tools
}

# Use processor count for service tuning
$worker_count = $facts['processors']['count']

registry_value { 'HKLM\SOFTWARE\MyApp\WorkerThreads':
  ensure => present,
  type   => dword,
  data   => $worker_count * 2,
}
```

---

## Custom Facts on Windows — PowerShell

Write PowerShell-based external facts in `facts.d/`:

```powershell
# modules/myapp/facts.d/myapp_version.ps1
# External fact — output must be KEY=VALUE pairs

$installPath = 'C:\Program Files\MyApp'
$versionFile = Join-Path $installPath 'version.txt'

if (Test-Path $versionFile) {
    $version = Get-Content $versionFile -Raw | ForEach-Object { $_.Trim() }
    Write-Output "myapp_version=$version"
    Write-Output "myapp_installed=true"
} else {
    Write-Output "myapp_version=none"
    Write-Output "myapp_installed=false"
}
```

```powershell
# Structured external fact (JSON output)
# modules/myapp/facts.d/iis_state.ps1

$sites = Get-Website | Select-Object -Property Name, State, PhysicalPath |
         ConvertTo-Json -Compress

# Output as JSON for structured facts
Write-Output "iis_sites=$sites"
```

---

## Custom Facts — Ruby-based (cross-platform)

Ruby facts run on both Windows and Linux if written carefully:

```ruby
# modules/myapp/lib/facter/myapp_state.rb
Facter.add('myapp_state') do
  confine :kernel => 'windows'    # only collect on Windows

  setcode do
    result = {}

    # Use Ruby's Win32 registry access
    begin
      require 'win32/registry'
      Win32::Registry::HKEY_LOCAL_MACHINE.open(
        'SOFTWARE\MyApp'
      ) do |reg|
        result['version']     = reg.read_s('Version')
        result['install_dir'] = reg.read_s('InstallDir')
        result['licensed']    = reg.read_i('Licensed') == 1
      end
    rescue Win32::Registry::Error
      result['installed'] = false
    end

    result
  end
end
```

---

<!-- _class: lead -->

# Part 8 — Templates and Files on Windows

---

## EPP Templates on Windows — Path Handling

```puppet
# EPP template parameter passing
file { 'C:/ProgramData/MyApp/config.ini':
  ensure  => file,
  content => epp('myapp/config.ini.epp', {
    db_host    => lookup('myapp::db_host'),
    db_port    => lookup('myapp::db_port'),
    app_name   => $facts['networking']['hostname'],
    log_path   => 'C:/ProgramData/MyApp/logs',
    data_path  => 'C:/ProgramData/MyApp/data',
  }),
}
```

`templates/config.ini.epp`:

```
<%- | String $db_host,
      Integer $db_port,
      String  $app_name,
      String  $log_path,
      String  $data_path,
| -%>
# Managed by Puppet — do not edit manually
[database]
host=<%= $db_host %>
port=<%= $db_port %>

[application]
name=<%= $app_name %>
log_path=<%= $log_path %>
data_path=<%= $data_path %>
```

---

## Line Endings — CRLF on Windows

Windows applications typically expect **CRLF** (`\r\n`) line endings. Puppet does not convert automatically.

```puppet
# Option 1 — Use stdlib's dos2unix / unix2dos functions
# requires puppetlabs-stdlib
file { 'C:/MyApp/config.txt':
  ensure  => file,
  content => dos_to_unix(template('myapp/config.txt.erb')),
}

# Option 2 — Write CRLF explicitly in EPP
# In the template, use \r\n at line ends:
# key=value\r\n
# OR set the file_line_separator in the template itself
```

Best practice — use a template wrapper function in `lib/puppet/functions/`:

```puppet
# In a manifest
file { 'C:/MyApp/config.txt':
  ensure  => file,
  content => windows_epp('myapp/config.txt.epp', { key => 'value' }),
}
```

> For most modern Windows applications (since Windows 10/Server 2019), **LF-only** line endings work fine. Only older tools (Notepad pre-2018, some legacy apps) strictly require CRLF. Test your specific application.

---

## File Encoding

Windows applications often expect **UTF-16 LE with BOM** or **UTF-8 with BOM** for certain file types (e.g., PowerShell scripts, some config files).

```puppet
# Force UTF-8 BOM via exec (when file resource encoding isn't enough)
exec { 'write-ps-script-utf8bom':
  command  => @("PS"/L),
    $content = Get-Content 'C:\Scripts\setup.ps1' -Raw
    [System.IO.File]::WriteAllText(
      'C:\Scripts\setup.ps1',
      $content,
      [System.Text.Encoding]::UTF8
    )
    | PS
  provider    => powershell,
  refreshonly => true,
  subscribe   => File['C:/Scripts/setup.ps1'],
}
```

> For Puppet-managed files, UTF-8 without BOM is generally the safest choice — PowerShell 5.1+ and all modern Windows apps handle it correctly.

---

<!-- _class: lead -->

# Part 9 — Cross-Platform Modules

---

## The Cross-Platform Module Pattern

![w:900](../assets/cross-platform-module.svg)

---

## Detecting the Platform in Puppet Code

```puppet
# Primary switch: $facts['kernel']
# 'Linux'   — all Linux distributions
# 'windows' — all Windows versions
# 'Darwin'  — macOS

case $facts['kernel'] {
  'windows': {
    $cfg_dir     = 'C:/ProgramData/MyApp'
    $pkg_name    = 'MyApp'
    $svc_name    = 'MyAppService'
    $pkg_provider = 'chocolatey'
  }
  'Linux': {
    $cfg_dir     = '/etc/myapp'
    $pkg_name    = 'myapp'
    $svc_name    = 'myapp'
    $pkg_provider = undef   # use system default (apt/yum)
  }
  default: {
    fail("Unsupported kernel: ${facts['kernel']}")
  }
}
```

```puppet
# More granular — $facts['os']['family']
# 'windows' → all Windows
# 'Debian'  → Ubuntu, Debian
# 'RedHat'  → RHEL, Rocky, AlmaLinux, CentOS, Fedora
# 'Suse'    → openSUSE, SLES
```

---

## Roles and Profiles for Mixed Estates

```puppet
# site.pp — classify by certname pattern or trusted fact
node /^win/ {
  include role::windows_server
}

node /^web/ {
  include role::webserver    # cross-platform — runs on Linux or Windows
}
```

```puppet
# profile/manifests/base.pp — truly cross-platform
class profile::base {
  # These work on both platforms
  class { 'ntp':
    servers => ['0.pool.ntp.org', '1.pool.ntp.org'],
  }

  # Platform-specific additions
  if $facts['kernel'] == 'windows' {
    include profile::base::windows
  } elsif $facts['os']['family'] == 'Debian' {
    include profile::base::debian
  } elsif $facts['os']['family'] == 'RedHat' {
    include profile::base::redhat
  }
}
```

---

## Hiera — Platform-Specific Data Separation

```yaml
# hiera.yaml — add OS family and kernel tiers
---
version: 5
hierarchy:
  - name: "Node-specific data"
    path: "nodes/%{trusted.certname}.yaml"

  - name: "Role data"
    path: "roles/%{lookup('role')}.yaml"

  - name: "OS Family data"
    path: "os/%{facts.os.family}.yaml"

  - name: "Kernel data"
    path: "kernel/%{facts.kernel}.yaml"

  - name: "Common data"
    path: "common.yaml"

defaults:
  data_hash: yaml_data
  datadir: data
```

```yaml
# data/kernel/windows.yaml
profile::base::packages:
  - 'googlechrome'
  - '7zip'
  - 'notepadplusplus'
  - 'putty'

profile::base::services_disabled:
  - 'Telnet'
  - 'RemoteRegistry'
```

---

## Module `metadata.json` — Declare Windows Support

```json
{
  "name": "myorg-myapp",
  "version": "1.0.0",
  "author": "myorg",
  "operatingsystem_support": [
    {
      "operatingsystem": "Ubuntu",
      "operatingsystemrelease": ["20.04", "22.04"]
    },
    {
      "operatingsystem": "RedHat",
      "operatingsystemrelease": ["8", "9"]
    },
    {
      "operatingsystem": "windows",
      "operatingsystemrelease": [
        "2016",
        "2019",
        "2022",
        "10",
        "11"
      ]
    }
  ],
  "dependencies": [
    { "name": "puppetlabs-chocolatey",  "version_requirement": ">= 6.0.0 < 8.0.0" },
    { "name": "puppetlabs-registry",    "version_requirement": ">= 2.0.0 < 4.0.0" },
    { "name": "puppetlabs-stdlib",      "version_requirement": ">= 8.0.0 < 10.0.0" }
  ]
}
```

---

<!-- _class: lead -->

# Part 10 — Testing Windows Puppet Code

---

## PDK on Windows

The Puppet Development Kit (PDK) runs natively on Windows:

```powershell
# Install PDK via Chocolatey
choco install pdk --yes

# Or download the MSI from https://puppet.com/try-puppet/puppet-development-kit/

# Verify
pdk --version

# Create a new module
pdk new module myorg-myapp
cd myorg-myapp

# Validate syntax
pdk validate

# Run unit tests
pdk test unit
```

---

## rspec-puppet for Cross-Platform Modules

Testing cross-platform code requires platform-specific contexts:

```ruby
# spec/classes/myapp_spec.rb
require 'spec_helper'

describe 'myapp' do
  # Test on Linux (default)
  context 'on Ubuntu 22.04' do
    let(:facts) do
      {
        os: { family: 'Debian', name: 'Ubuntu',
              release: { full: '22.04' } },
        kernel: 'Linux',
      }
    end

    it { is_expected.to compile.with_all_deps }
    it { is_expected.to contain_package('myapp').with_provider(nil) }
    it { is_expected.to contain_service('myapp').with_ensure('running') }
    it { is_expected.to contain_file('/etc/myapp/config.ini') }
  end

  # Test on Windows
  context 'on Windows Server 2022' do
    let(:facts) do
      {
        os: { family: 'windows', name: 'windows',
              windows: { product_name: 'Windows Server 2022 Standard',
                         installation_type: 'Server' } },
        kernel: 'windows',
      }
    end

    it { is_expected.to compile.with_all_deps }
    it { is_expected.to contain_package('MyApp').with_provider('chocolatey') }
    it { is_expected.to contain_service('MyAppService').with_ensure('running') }
    it { is_expected.to contain_file('C:/ProgramData/MyApp/config.ini') }
  end
end
```

---

## rspec-puppet — Testing Registry and ACL Resources

```ruby
context 'on Windows' do
  let(:facts) { windows_facts }

  # Verify registry resources
  it do
    is_expected.to contain_registry_value(
      'HKLM\SOFTWARE\MyApp\InstallDir'
    ).with(
      ensure: 'present',
      type:   'string',
      data:   'C:\Program Files\MyApp',
    )
  end

  # Verify ACL resources
  it do
    is_expected.to contain_acl('C:/ProgramData/MyApp').with(
      purge: false,
    )
  end

  # Verify Chocolatey packages
  it do
    is_expected.to contain_package('googlechrome').with(
      ensure:   'installed',
      provider: 'chocolatey',
    )
  end

  # Verify the Chocolatey class is included
  it { is_expected.to contain_class('chocolatey') }
end
```

---

## Acceptance Testing with Litmus on Windows

Litmus can provision Windows VMs and run Puppet against them:

```ruby
# spec/spec_helper_acceptance.rb
require 'puppet_litmus'
require 'litmus_helper'
include PuppetLitmus
```

```yaml
# provision.yaml — define Windows targets
---
default:
  provisioner: vagrant
  images:
    - 'gusztavvargadr/windows-server-2022-standard'   # Windows Server 2022

# Or with WinRM connection
winrm:
  provisioner: abs
  images:
    - 'win-2022-x86_64'
```

```bash
# Provision, install Puppet, run tests, tear down
bundle exec rake 'litmus:provision_list[default]'
bundle exec rake litmus:install_agent
bundle exec rake litmus:install_module
bundle exec rake litmus:acceptance:parallel
bundle exec rake litmus:tear_down
```

---

## Security Hardening with Puppet on Windows

Use Puppet to enforce the CIS Windows benchmarks:

```puppet
# profile/manifests/windows/hardening.pp
class profile::windows::hardening {

  # Disable legacy SMBv1
  registry_value { 'HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters\SMB1':
    ensure => present,
    type   => dword,
    data   => 0,
  }

  # Enforce TLS 1.2 minimum
  registry_value { 'HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Server\Enabled':
    ensure => present,
    type   => dword,
    data   => 0,
  }

  registry_value { 'HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server\Enabled':
    ensure => present,
    type   => dword,
    data   => 1,
  }

  # Disable autorun
  registry_value { 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer\NoDriveTypeAutoRun':
    ensure => present,
    type   => dword,
    data   => 255,
  }

  # Disable guest account
  user { 'Guest':
    ensure => present,
    managehome => false,
  }
}
```

---

## Summary — Windows with Puppet

| Topic | Key takeaway |
|---|---|
| **Installation** | MSI with `PUPPET_SERVER` property — same cert workflow as Linux |
| **Package management** | Use Chocolatey — `puppet module install puppetlabs-chocolatey` |
| **Files** | Forward slashes work everywhere; CRLF only when required |
| **Services** | `service` resource maps directly to SCM; `enable => delayed` works |
| **Registry** | `puppetlabs-registry` — `registry_key` + `registry_value` |
| **Permissions** | `puppetlabs-acl` for production ACL management |
| **IIS** | `puppetlabs-iis` wraps IIS DSC resources cleanly |
| **DSC** | Use when no native Puppet module exists; `dsc_lite` as fallback |
| **Facts** | `$facts['kernel'] == 'windows'` for branching |
| **Templates** | EPP works identically; be aware of line endings |
| **Cross-platform** | Branch on `$facts['kernel']`; split data in Hiera |
| **Testing** | rspec-puppet with Windows fact contexts; Litmus with WinRM |

---

## Next Steps

1. Complete the Day 4 exercises:
   - Exercise 1: Install Windows agent and connect to your Puppet Server
   - Exercise 2: Manage Windows resources — packages, registry, services, files, ACLs
   - Exercise 3: Build a cross-platform module and write DSC-backed IIS configuration

2. Explore these Puppet Forge modules:
   - `puppet module install puppetlabs-chocolatey`
   - `puppet module install puppetlabs-registry`
   - `puppet module install puppetlabs-acl`
   - `puppet module install puppetlabs-iis`
   - `puppet module install puppet-windowsfeature`

3. Read the Puppet Windows documentation:
   - `https://www.puppet.com/docs/puppet/latest/install_agents.html#install-windows-agents`
   - `https://www.puppet.com/docs/puppet/latest/resources_windows_common.html`
