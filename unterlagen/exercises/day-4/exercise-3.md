# Exercise 3 — Cross-Platform Modules and DSC-Backed IIS Management

**Estimated time:** 75–90 minutes

## Objective

Build a `webserver` module that works on both Linux (nginx) and Windows (IIS), with platform detection handled cleanly through `$facts['kernel']` and Hiera. In the second half, configure a full IIS website using `puppetlabs-iis` (which is DSC-backed), including application pools, SSL bindings, and application-level settings. By the end you will understand how to design modules for mixed estates and how the DSC bridge integrates transparently into Puppet code.

---

## Prerequisites

- Exercise 1 and Exercise 2 completed
- Windows node is connected to the Puppet Server
- Linux node (`agent01`) from Day 1 is still connected
- IIS is available on the Windows node (Windows Server 2019/2022 or Windows 10/11 Pro — IIS feature not yet installed; we will install it via Puppet)

---

## Part 1 — The Cross-Platform `webserver` Module (30 min)

### Step 1 — Create the module skeleton

On the **Puppet Server**:

```bash
cd /etc/puppetlabs/code/environments/production/modules
mkdir -p webserver/{manifests,templates,files,data,spec/classes}
```

Install the IIS module:

```bash
sudo puppet module install puppetlabs-iis
sudo puppet module install puppetlabs-apache    # for the Linux side (if not already installed)
```

### Step 2 — Write `init.pp` — the cross-platform entry point

Create `/etc/puppetlabs/code/environments/production/modules/webserver/manifests/init.pp`:

```puppet
# @summary Manages a web server on both Linux (nginx/Apache) and Windows (IIS).
#
# @param http_port
#   TCP port for unencrypted HTTP traffic.
# @param https_port
#   TCP port for encrypted HTTPS traffic.
# @param doc_root
#   Root directory for static web content.
# @param server_name
#   Primary hostname for the virtual host / IIS site.
# @param vhosts
#   Hash of additional virtual hosts (name => { ... }) to configure.
class webserver (
  Integer        $http_port   = 80,
  Integer        $https_port  = 443,
  String         $doc_root    = lookup('webserver::doc_root'),
  String         $server_name = $facts['networking']['fqdn'],
  Hash           $vhosts      = {},
) {
  case $facts['kernel'] {
    'windows': {
      contain webserver::windows
    }
    'Linux': {
      contain webserver::linux
    }
    default: {
      fail("webserver: unsupported kernel '${facts['kernel']}'")
    }
  }
}
```

### Step 3 — Write `linux.pp` — the Linux implementation

Create `/etc/puppetlabs/code/environments/production/modules/webserver/manifests/linux.pp`:

```puppet
# @summary Linux web server implementation (nginx).
# @api private
class webserver::linux {
  # Install nginx
  package { 'nginx':
    ensure => installed,
  }

  # Create document root
  file { $webserver::doc_root:
    ensure  => directory,
    owner   => 'www-data',
    group   => 'www-data',
    mode    => '0755',
    require => Package['nginx'],
  }

  # Deploy a placeholder index page
  file { "${webserver::doc_root}/index.html":
    ensure  => file,
    content => epp('webserver/index.html.epp', {
      server_name => $webserver::server_name,
      kernel      => $facts['kernel'],
      os_name     => $facts['os']['name'],
    }),
    owner   => 'www-data',
    group   => 'www-data',
    mode    => '0644',
    require => File[$webserver::doc_root],
    notify  => Service['nginx'],
  }

  # nginx vhost configuration
  file { "/etc/nginx/sites-available/${webserver::server_name}.conf":
    ensure  => file,
    content => epp('webserver/nginx-vhost.conf.epp', {
      server_name => $webserver::server_name,
      doc_root    => $webserver::doc_root,
      http_port   => $webserver::http_port,
    }),
    require => Package['nginx'],
    notify  => Service['nginx'],
  }

  file { "/etc/nginx/sites-enabled/${webserver::server_name}.conf":
    ensure  => link,
    target  => "/etc/nginx/sites-available/${webserver::server_name}.conf",
    require => File["/etc/nginx/sites-available/${webserver::server_name}.conf"],
    notify  => Service['nginx'],
  }

  service { 'nginx':
    ensure => running,
    enable => true,
  }
}
```

### Step 4 — Write `windows.pp` — the Windows IIS implementation

Create `/etc/puppetlabs/code/environments/production/modules/webserver/manifests/windows.pp`:

```puppet
# @summary Windows web server implementation (IIS).
# @api private
class webserver::windows {

  # Step 1: Install IIS Windows Feature (uses DSC internally)
  include iis

  # Step 2: Create the document root directory
  file { $webserver::doc_root:
    ensure  => directory,
    require => Class['iis'],
  }

  # Step 3: Deploy the index page
  file { "${webserver::doc_root}/index.html":
    ensure  => file,
    content => epp('webserver/index.html.epp', {
      server_name => $webserver::server_name,
      kernel      => $facts['kernel'],
      os_name     => $facts['os']['windows']['product_name'],
    }),
    require => File[$webserver::doc_root],
  }

  # Step 4: Create an Application Pool
  iis_application_pool { 'WebserverPool':
    ensure                  => present,
    state                   => started,
    managed_runtime_version => 'v4.0',
    managed_pipeline_mode   => 'Integrated',
    identity_type           => 'ApplicationPoolIdentity',
    start_mode              => 'OnDemand',
    idle_timeout            => '00:20:00',
    require                 => Class['iis'],
  }

  # Step 5: Create the IIS website
  iis_site { $webserver::server_name:
    ensure          => present,
    physpath        => $webserver::doc_root,
    bindings        => [
      {
        protocol   => 'http',
        port       => $webserver::http_port,
        hostheader => $webserver::server_name,
      },
    ],
    applicationpool => 'WebserverPool',
    logformat       => 'W3C',
    logpath         => 'C:/inetpub/logs/LogFiles',
    require         => [
      Iis_application_pool['WebserverPool'],
      File[$webserver::doc_root],
    ],
  }

  # Ensure the IIS service is running
  service { 'W3SVC':
    ensure  => running,
    enable  => true,
    require => Class['iis'],
  }
}
```

### Step 5 — Create the shared EPP templates

Create `/etc/puppetlabs/code/environments/production/modules/webserver/templates/index.html.epp`:

```
<%- | String $server_name,
      String $kernel,
      String $os_name,
| -%>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Managed by Puppet — <%= $server_name %></title>
  <style>
    body { font-family: Arial, sans-serif; max-width: 600px; margin: 80px auto; color: #333; }
    .badge { background: #e65100; color: white; padding: 4px 10px; border-radius: 4px; font-size: 12px; }
    .info  { background: #f5f5f5; border-left: 4px solid #9370DB; padding: 12px 16px; margin: 20px 0; }
  </style>
</head>
<body>
  <h1><span class="badge">PUPPET</span> <%= $server_name %></h1>
  <p>This page is <strong>managed by Puppet</strong>. Do not edit it manually.</p>
  <div class="info">
    <strong>Kernel:</strong> <%= $kernel %><br>
    <strong>OS:</strong>     <%= $os_name %><br>
    <strong>Node:</strong>   <%= $server_name %>
  </div>
  <p><em>Any manual changes will be overwritten on the next Puppet run.</em></p>
</body>
</html>
```

Create `/etc/puppetlabs/code/environments/production/modules/webserver/templates/nginx-vhost.conf.epp`:

```
<%- | String  $server_name,
      String  $doc_root,
      Integer $http_port,
| -%>
# Managed by Puppet — do not edit
server {
    listen      <%= $http_port %>;
    server_name <%= $server_name %>;
    root        <%= $doc_root %>;
    index       index.html index.htm;

    access_log  /var/log/nginx/<%= $server_name %>-access.log;
    error_log   /var/log/nginx/<%= $server_name %>-error.log;

    location / {
        try_files $uri $uri/ =404;
    }
}
```

### Step 6 — Add Hiera data for platform-specific document roots

Create `/etc/puppetlabs/code/environments/production/data/os/windows.yaml`:

```yaml
webserver::doc_root: 'C:/inetpub/wwwroot/managed'
```

Create `/etc/puppetlabs/code/environments/production/data/os/Debian.yaml`:

```yaml
webserver::doc_root: '/var/www/managed'
```

Create `/etc/puppetlabs/code/environments/production/data/os/RedHat.yaml`:

```yaml
webserver::doc_root: '/var/www/html/managed'
```

### Step 7 — Classify both nodes

Update `site.pp`:

```puppet
node 'agent01.example.com' {
  include webserver
}

node 'win01.example.com' {
  include windows_baseline
  include webserver
}
```

---

## Part 2 — Apply and Test on Both Platforms (15 min)

### Step 1 — Apply on the Linux node

On the **Linux agent** (`agent01`):

```bash
sudo puppet agent --test
```

Verify:

```bash
# Is nginx installed and running?
systemctl status nginx

# Does the document root exist?
ls -la /var/www/managed/

# Is the index page deployed?
cat /var/www/managed/index.html

# Is the vhost configured?
cat /etc/nginx/sites-available/agent01.example.com.conf

# Is the vhost symlinked?
ls -la /etc/nginx/sites-enabled/

# Can we GET the page?
curl -s http://localhost/ | grep 'PUPPET'
```

### Step 2 — Apply on the Windows node

On the **Windows agent**:

```powershell
puppet agent --test
```

This run will:
1. Install the IIS Windows Feature (takes ~2 minutes on first run — IIS must be downloaded)
2. Create the application pool
3. Create the IIS site
4. Deploy the index.html

```powershell
# Verify IIS is installed
Get-WindowsFeature -Name Web-Server

# Verify the site exists
Get-Website

# Verify the app pool exists
Get-WebConfiguration 'system.applicationHost/applicationPools/add' |
    Where-Object { $_.name -eq 'WebserverPool' }

# Verify the document root exists
Test-Path 'C:\inetpub\wwwroot\managed'

# Read the deployed file
Get-Content 'C:\inetpub\wwwroot\managed\index.html'

# Fetch the page via HTTP
Invoke-WebRequest -Uri "http://localhost/" -UseBasicParsing | Select-Object -ExpandProperty Content
```

---

## Part 3 — DSC Deep Dive: Advanced IIS Configuration (20 min)

Now we use DSC directly for configurations that go beyond what `puppetlabs-iis` exposes.

### Step 1 — Add HTTPS binding with a self-signed certificate

Create `/etc/puppetlabs/code/environments/production/modules/webserver/manifests/windows_ssl.pp`:

```puppet
# @summary Adds HTTPS support to the IIS site using a self-signed certificate.
# @api private
class webserver::windows_ssl {

  # Generate a self-signed certificate using DSC
  dsc { 'self-signed-cert':
    resource_name => 'xCertificateDsc::SelfSignedCertificate',
    module        => { name => 'xCertificate', version => '3.2.0.0' },
    properties    => {
      subject            => "CN=${webserver::server_name}",
      friendlyname       => "Puppet-managed cert for ${webserver::server_name}",
      keyusage           => ['DigitalSignature', 'KeyEncipherment'],
      enhancedkeyusage   => ['Server Authentication'],
      subjectalternativename => "dns=${webserver::server_name}",
      certificatestore   => 'My',
      exportable         => false,
    },
  }

  # Retrieve the cert thumbprint using PowerShell and store in a fact
  # (In practice, use a fact to look up the thumbprint after creation)
  exec { 'add-https-binding':
    command  => @("PS"/L),
      $cert = Get-ChildItem Cert:\LocalMachine\My |
        Where-Object { $_.Subject -like "CN=${webserver::server_name}*" } |
        Sort-Object NotBefore -Descending |
        Select-Object -First 1
      if ($cert) {
        $site = Get-Website -Name "${webserver::server_name}" -ErrorAction SilentlyContinue
        if ($site) {
          $existingBinding = Get-WebBinding -Name "${webserver::server_name}" -Protocol https -ErrorAction SilentlyContinue
          if (-not $existingBinding) {
            New-WebBinding -Name "${webserver::server_name}" -Protocol https -Port ${webserver::https_port} -HostHeader "${webserver::server_name}"
            (Get-WebBinding -Name "${webserver::server_name}" -Protocol https).AddSslCertificate($cert.Thumbprint, "my")
          }
        }
      }
      | PS
    provider => powershell,
    unless   => @("PS"/L),
      $binding = Get-WebBinding -Name "${webserver::server_name}" -Protocol https -ErrorAction SilentlyContinue
      if ($binding) { exit 0 } else { exit 1 }
      | PS
    require  => [Dsc['self-signed-cert'], Iis_site[$webserver::server_name]],
  }
}
```

### Step 2 — Install the xCertificate DSC module on all Windows nodes

This is done via the `dsc` module's dependencies mechanism. Add to `Puppetfile` on the Puppet Server:

```ruby
# Puppetfile — this tells r10k / Puppet to deploy the module
mod 'puppet-dsc_lite', '1.4.0'
```

Or install ad-hoc:

```bash
sudo puppet module install puppet-dsc_lite
```

On the Windows node, install the PowerShell DSC module to the system module path:

```powershell
# This runs on the Windows node
Install-Module -Name xCertificate -RequiredVersion 3.2.0.0 -Force -Scope AllUsers
```

> **In production:** Use a Puppet `exec` resource to install PSGallery modules, or pre-bake them into a custom base image.

### Step 3 — Using `dsc_lite` for Windows Features not in `puppetlabs-iis`

Enable additional IIS features with full DSC power:

```puppet
# In webserver::windows — add IIS optional features
[
  'Web-Asp-Net45',
  'Web-Mgmt-Console',
  'Web-Http-Logging',
  'Web-Stat-Compression',
].each |$feature| {
  dsc { "iis-feature-${feature}":
    resource_name => 'WindowsFeature',
    module        => 'PSDesiredStateConfiguration',
    properties    => {
      ensure => 'Present',
      name   => $feature,
    },
    require => Class['iis'],
  }
}
```

---

## Part 4 — Write rspec-puppet Tests for the Cross-Platform Module (20 min)

### Step 1 — Create the spec directory and spec_helper

```bash
# On the Puppet Server (or your development workstation with PDK installed)
cd /etc/puppetlabs/code/environments/production/modules/webserver
pdk new module webserver   # creates skeleton if not already done

# Or create spec_helper manually
mkdir -p spec/classes
```

Create `spec/spec_helper.rb`:

```ruby
require 'puppetlabs_spec_helper/module_spec_helper'
require 'rspec-puppet-facts'

include RspecPuppetFacts

RSpec.configure do |c|
  c.before :each do
    Puppet.settings[:strict] = :warning
  end
end
```

### Step 2 — Write tests for both platforms

Create `spec/classes/init_spec.rb`:

```ruby
require 'spec_helper'

describe 'webserver' do

  # ── Linux (Ubuntu 22.04) ────────────────────────────────────────────────────
  context 'on Ubuntu 22.04' do
    let(:facts) do
      {
        kernel: 'Linux',
        os: {
          family:  'Debian',
          name:    'Ubuntu',
          release: { full: '22.04', major: '22' },
        },
        networking: {
          fqdn:   'agent01.example.com',
          domain: 'example.com',
        },
      }
    end

    let(:params) do
      {
        doc_root:    '/var/www/managed',
        server_name: 'agent01.example.com',
      }
    end

    it { is_expected.to compile.with_all_deps }
    it { is_expected.to contain_class('webserver::linux') }
    it { is_expected.not_to contain_class('webserver::windows') }

    it { is_expected.to contain_package('nginx').with_ensure('installed') }

    it {
      is_expected.to contain_file('/var/www/managed').with(
        ensure: 'directory',
        owner:  'www-data',
        group:  'www-data',
      )
    }

    it {
      is_expected.to contain_file('/var/www/managed/index.html').with(
        ensure: 'file',
      )
    }

    it {
      is_expected.to contain_service('nginx').with(
        ensure: 'running',
        enable: true,
      )
    }

    it {
      is_expected.to contain_file('/etc/nginx/sites-available/agent01.example.com.conf')
    }
  end

  # ── Windows Server 2022 ─────────────────────────────────────────────────────
  context 'on Windows Server 2022' do
    let(:facts) do
      {
        kernel: 'windows',
        os: {
          family:  'windows',
          name:    'windows',
          windows: {
            product_name:      'Windows Server 2022 Standard',
            installation_type: 'Server',
          },
          release: { full: '10.0.20348', major: '2022' },
        },
        networking: {
          fqdn:   'win01.example.com',
          domain: 'example.com',
        },
      }
    end

    let(:params) do
      {
        doc_root:    'C:/inetpub/wwwroot/managed',
        server_name: 'win01.example.com',
        http_port:   80,
      }
    end

    it { is_expected.to compile.with_all_deps }
    it { is_expected.to contain_class('webserver::windows') }
    it { is_expected.not_to contain_class('webserver::linux') }
    it { is_expected.not_to contain_package('nginx') }

    it {
      is_expected.to contain_iis_application_pool('WebserverPool').with(
        ensure: 'present',
        state:  'started',
      )
    }

    it {
      is_expected.to contain_iis_site('win01.example.com').with(
        ensure:          'present',
        physpath:        'C:/inetpub/wwwroot/managed',
        applicationpool: 'WebserverPool',
      )
    }

    it {
      is_expected.to contain_file('C:/inetpub/wwwroot/managed').with(
        ensure: 'directory',
      )
    }

    it {
      is_expected.to contain_service('W3SVC').with(
        ensure: 'running',
        enable: true,
      )
    }
  end

  # ── Unsupported OS ───────────────────────────────────────────────────────────
  context 'on an unsupported kernel' do
    let(:facts) do
      {
        kernel: 'FreeBSD',
        os:     { family: 'FreeBSD' },
        networking: { fqdn: 'bsd01.example.com', domain: 'example.com' },
      }
    end

    let(:params) do
      {
        doc_root:    '/usr/local/www/managed',
        server_name: 'bsd01.example.com',
      }
    end

    it {
      is_expected.to raise_error(Puppet::PreformattedError, /unsupported kernel/)
    }
  end
end
```

### Step 3 — Run the tests with PDK

```bash
# On a workstation with PDK installed (or the Puppet Server with PDK)
cd /etc/puppetlabs/code/environments/production/modules/webserver
pdk test unit
```

Expected output:

```
Running unit tests...
  webserver
    on Ubuntu 22.04
      should compile with all deps                      [PASSED]
      should contain Class[webserver::linux]            [PASSED]
      should contain Package[nginx]                     [PASSED]
      ...
    on Windows Server 2022
      should compile with all deps                      [PASSED]
      should contain Class[webserver::windows]          [PASSED]
      should contain Iis_application_pool[WebserverPool][PASSED]
      ...
    on an unsupported kernel
      should raise error                                [PASSED]

Finished in 1.23 seconds
11 examples, 0 failures
```

---

## Part 5 — Update Module Metadata for Windows Support

Open `metadata.json` for the `webserver` module and add Windows to `operatingsystem_support`:

```json
{
  "name": "myorg-webserver",
  "version": "1.0.0",
  "author": "myorg",
  "license": "Apache-2.0",
  "summary": "Cross-platform web server module — nginx on Linux, IIS on Windows",
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
      "operatingsystemrelease": ["2019", "2022", "10", "11"]
    }
  ],
  "dependencies": [
    { "name": "puppetlabs-iis",     "version_requirement": ">= 8.0.0 < 10.0.0" },
    { "name": "puppetlabs-stdlib",  "version_requirement": ">= 8.0.0 < 10.0.0" }
  ],
  "requirements": [
    { "name": "puppet", "version_requirement": ">= 7.0.0 < 9.0.0" }
  ]
}
```

---

## Part 6 — Challenge Exercises

### Challenge A — Add HTTPS to the Linux side

Extend `webserver::linux` with a `manage_ssl` parameter. When `true`:
1. Install `certbot` via the `package` resource
2. Use an `exec` resource to request a Let's Encrypt certificate
3. Add HTTPS server block to the nginx vhost template
4. Ensure the cert renewal `cron` job is managed

### Challenge B — IIS Application from Hiera

Add a `webserver::iis_applications` parameter that accepts a hash:

```yaml
webserver::iis_applications:
  api:
    physpath: 'C:/inetpub/wwwroot/managed/api'
    applicationpool: 'ApiPool'
  admin:
    physpath: 'C:/inetpub/wwwroot/managed/admin'
    applicationpool: 'WebserverPool'
```

Iterate over the hash in `webserver::windows` to create `iis_application` resources.

### Challenge C — Custom Fact for Server Role

Write a PowerShell external fact in `facts.d/windows_role.ps1` that:
1. Reads the value of `HKLM\SOFTWARE\PuppetLabs\Management\Role`
2. Returns it as `windows_puppet_role=<value>`

Then use this fact in `site.pp` for node classification:

```puppet
# site.pp
node /^win/ {
  case $facts['windows_puppet_role'] {
    'webserver': { include webserver }
    'database':  { include role::windows_database }
    default:     { include windows_baseline }
  }
}
```

---

## Summary

You have:
1. Built a `webserver` module that works on both Linux and Windows with a single `include webserver`
2. Used `$facts['kernel']` to branch into platform-specific sub-classes
3. Used Hiera to provide platform-specific data (`doc_root`) transparently
4. Configured IIS with application pools and HTTP bindings via `puppetlabs-iis`
5. Used `dsc_lite` for DSC resources not covered by dedicated Puppet modules
6. Written rspec-puppet tests that verify both Linux and Windows behavior
7. Updated `metadata.json` to declare Windows OS support
8. Understood when to use native Puppet resources vs. DSC bridge

---

## Key Takeaways from Day 4

| Concept | Implementation |
|---|---|
| Windows agent | MSI install with `PUPPET_SERVER` property — identical cert workflow to Linux |
| Packages | `puppetlabs-chocolatey` — `package { 'git': provider => chocolatey }` |
| Registry | `puppetlabs-registry` — `registry_key` + `registry_value` |
| Permissions | `puppetlabs-acl` — multi-ACE, break-inheritance, deny rules |
| IIS | `puppetlabs-iis` — sites, app pools, bindings via DSC |
| DSC | `dsc_lite` for anything in PSGallery not yet wrapped in a Forge module |
| Platform detection | `$facts['kernel']` == `'windows'` vs `'Linux'` |
| Data separation | Hiera `kernel/%{facts.kernel}.yaml` for platform defaults |
| Testing | rspec-puppet contexts with Windows fact hashes |
| Security | Passwords always in `Sensitive()` + Hiera eyaml; SMBv1 disabled |
