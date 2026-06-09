# Exercise 1 — Install the Puppet Agent on Windows and Connect to the Puppet Server

**Estimated time:** 60–75 minutes

## Objective

Install the `puppet-agent` MSI on a Windows node, connect it to the Puppet Server you set up in Day 1, sign its certificate, and verify that the node receives and applies a catalog. By the end of this exercise you will understand the full bootstrap process for Windows nodes — including the differences from Linux nodes and the Windows-specific configuration file locations.

---

## Prerequisites

- The Puppet Server from Day 1 exercises is running and accessible
- One Windows virtual machine (Windows Server 2019, 2022, or Windows 10/11):
  - At least 2 vCPU, 4 GB RAM
  - PowerShell 5.1 or later (included with all supported Windows versions)
  - Administrator access
- Network connectivity between the Windows VM and the Puppet Server (port 8140)
- The Windows VM can resolve the Puppet Server hostname (set in `C:\Windows\System32\drivers\etc\hosts` if DNS is not configured)

---

## Part 1 — Prepare Name Resolution (5 min)

### Step 1 — Find the Puppet Server IP

On the **Puppet Server** (Linux):
```bash
ip addr show | grep 'inet '
# Note the IP address, e.g. 192.168.1.10
```

### Step 2 — Configure name resolution on the Windows node

Open PowerShell **as Administrator** on the Windows VM and add the Puppet Server to `hosts`:

```powershell
# Replace 192.168.1.10 with your Puppet Server's actual IP
$puppetIp = '192.168.1.10'
$hostsLine = "$puppetIp  puppet.example.com  puppet"
$hostsFile = 'C:\Windows\System32\drivers\etc\hosts'

# Check if the entry already exists
if (-not (Select-String -Path $hostsFile -Pattern 'puppet.example.com' -Quiet)) {
    Add-Content -Path $hostsFile -Value $hostsLine
    Write-Host "Added puppet.example.com to hosts file"
} else {
    Write-Host "Entry already exists"
}
```

### Step 3 — Verify connectivity

```powershell
# Verify name resolution
Resolve-DnsName puppet.example.com

# Verify network connectivity to port 8140
Test-NetConnection -ComputerName puppet.example.com -Port 8140
# TcpTestSucceeded should be True
```

> **Troubleshooting:** If `TcpTestSucceeded` is `False`, check the firewall on the Puppet Server:
> ```bash
> # On the Puppet Server (Linux)
> sudo ufw allow 8140/tcp   # Ubuntu
> sudo firewall-cmd --permanent --add-port=8140/tcp && sudo firewall-cmd --reload  # Rocky/RHEL
> ```

---

## Part 2 — Install the Puppet Agent (15 min)

### Step 1 — Download the MSI

```powershell
# Download the latest Puppet 8 agent MSI
$downloadUrl = 'https://downloads.puppet.com/windows/puppet8/puppet-agent-x64-latest.msi'
$installerPath = "$env:TEMP\puppet-agent.msi"

Write-Host "Downloading Puppet agent..."
Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath -UseBasicParsing
Write-Host "Download complete: $installerPath"
```

> **Offline environments:** Copy the MSI from `https://downloads.puppet.com/windows/puppet8/` to the Windows machine via a shared folder, USB, or `scp` from another machine.

### Step 2 — Install silently

```powershell
# Set your Puppet Server hostname
$puppetServer = 'puppet.example.com'
# Set a certname — use the FQDN of the Windows machine
$certname = "$env:COMPUTERNAME.example.com".ToLower()

Write-Host "Installing Puppet agent..."
Write-Host "  Server:   $puppetServer"
Write-Host "  Certname: $certname"

$msiArgs = @(
    '/qn',
    '/norestart',
    '/l*v', "$env:TEMP\puppet-agent-install.log",
    '/i', $installerPath,
    "PUPPET_SERVER=$puppetServer",
    "PUPPET_AGENT_CERTNAME=$certname",
    'PUPPET_AGENT_ENVIRONMENT=production',
    'PUPPET_AGENT_STARTUP_MODE=Manual'   # Manual for now — we'll start it ourselves
)

$install = Start-Process msiexec -ArgumentList $msiArgs -Wait -PassThru
if ($install.ExitCode -eq 0) {
    Write-Host "Puppet agent installed successfully"
} else {
    Write-Host "Installation failed with exit code: $($install.ExitCode)"
    Write-Host "Check log: $env:TEMP\puppet-agent-install.log"
}
```

### Step 3 — Verify the installation

```powershell
# Refresh environment variables in the current session
$env:PATH = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine')

# Check the version
puppet --version

# Verify the Puppet binaries directory
& "C:\Program Files\Puppet Labs\Puppet\bin\puppet.bat" --version
```

Expected output: `8.x.x` or similar.

---

## Part 3 — Review the Configuration (10 min)

### Step 1 — Locate and inspect `puppet.conf`

```powershell
# The main configuration file
notepad "C:\ProgramData\PuppetLabs\puppet\etc\puppet.conf"
```

The MSI will have pre-populated it based on your install parameters. It should look like:

```ini
[main]
certname    = win01.example.com
server      = puppet.example.com
environment = production
```

### Step 2 — Add useful agent settings

Open `puppet.conf` and add or verify these settings:

```ini
[main]
certname    = win01.example.com
server      = puppet.example.com
environment = production

[agent]
runinterval = 1800       # run every 30 minutes
waitforcert = 120        # wait up to 2 min for cert to be signed
report      = true       # send run reports to PuppetDB
```

Save and close the file.

### Step 3 — Explore the Windows data directory

```powershell
# See the full layout
Get-ChildItem 'C:\ProgramData\PuppetLabs\puppet\' -Recurse -Depth 2 |
    Select-Object FullName, Mode | Format-Table -AutoSize

# Key directories:
# C:\ProgramData\PuppetLabs\puppet\etc\ssl\   ← certificates (empty until first run)
# C:\ProgramData\PuppetLabs\puppet\cache\     ← cached catalog and reports
# C:\ProgramData\PuppetLabs\facter\facts.d\   ← external facts directory
```

---

## Part 4 — Submit the Certificate Signing Request (10 min)

### Step 1 — Trigger the first run (which generates the CSR)

In PowerShell (as Administrator):

```powershell
puppet agent --test
```

Expected output at this stage:
```
Info: Creating a new SSL key for win01.example.com
Info: Caching certificate for ca
Info: csr_attributes file loading from C:/ProgramData/PuppetLabs/puppet/etc/csr_attributes.yaml
Info: Creating a new SSL certificate request for win01.example.com
Info: Certificate Request fingerprint (SHA256): XX:XX:XX:...
Info: Caching certificate for ca
Exiting; no certificate found and waitforcert is disabled
```

The key lines are:
- `Creating a new SSL key` — the private key was generated
- `Creating a new SSL certificate request` — the CSR was submitted
- `Exiting; no certificate found` — waiting for the server to sign

### Step 2 — Sign the certificate on the Puppet Server

On the **Puppet Server** (Linux):

```bash
# List all pending certificate requests
sudo puppetserver ca list

# You should see something like:
# Requested Certificates:
#   win01.example.com  (SHA256) XX:XX:XX:...

# Sign the Windows node's certificate
sudo puppetserver ca sign --certname win01.example.com
```

Expected output:
```
Successfully signed certificate request for win01.example.com
```

---

## Part 5 — Trigger the First Successful Catalog Run (10 min)

### Step 1 — Re-run the agent (now the certificate is signed)

Back on the **Windows node** in PowerShell:

```powershell
puppet agent --test
```

Expected output (shortened):
```
Info: Using environment 'production'
Info: Retrieving pluginfacts
Info: Retrieving plugin
Info: Caching catalog for win01.example.com
Info: Applying configuration version '1718000000'
Notice: Applied catalog in 1.23 seconds
```

> If you see errors, check Part 6 (Troubleshooting) below.

### Step 2 — Examine what was applied

```powershell
# Show the last run summary
puppet agent --test --summarize

# Look at the detailed last run report
$reportPath = 'C:\ProgramData\PuppetLabs\puppet\cache\state\last_run_summary.yaml'
Get-Content $reportPath
```

### Step 3 — Verify the certificate files exist

```powershell
# The SSL directory should now contain:
Get-ChildItem 'C:\ProgramData\PuppetLabs\puppet\etc\ssl\' -Recurse |
    Select-Object FullName | Format-Table -AutoSize

# You should see:
# ...ssl\certs\win01.example.com.pem       ← signed certificate
# ...ssl\private_keys\win01.example.com.pem ← private key
# ...ssl\certs\ca.pem                       ← CA certificate
```

---

## Part 6 — Apply a Simple Windows-Specific Manifest (15 min)

Now let's classify the Windows node and apply something meaningful.

### Step 1 — Classify the node on the Puppet Server

On the **Puppet Server**, edit `site.pp`:

```bash
sudo nano /etc/puppetlabs/code/environments/production/manifests/site.pp
```

Add a node block for your Windows node (adjust the certname):

```puppet
# Existing Linux nodes
node 'agent01.example.com' {
  include webstack
}

# New Windows node
node 'win01.example.com' {
  # Ensure a directory exists
  file { 'C:/ProgramData/PuppetTest':
    ensure => directory,
  }

  # Manage a configuration file
  file { 'C:/ProgramData/PuppetTest/managed.txt':
    ensure  => file,
    content => "Managed by Puppet\nNode: ${trusted['certname']}\nEnvironment: ${environment}\n",
    require => File['C:/ProgramData/PuppetTest'],
  }

  # Ensure a registry key exists
  registry_key { 'HKLM\SOFTWARE\PuppetTest':
    ensure => present,
  }

  registry_value { 'HKLM\SOFTWARE\PuppetTest\ManagedBy':
    ensure => present,
    type   => string,
    data   => 'Puppet',
  }
}
```

> **Note:** The `registry_key` and `registry_value` resources require the `puppetlabs-registry` module. We will install it next.

### Step 2 — Install the `puppetlabs-registry` module on the server

```bash
sudo puppet module install puppetlabs-registry
```

### Step 3 — Apply the catalog on the Windows node

```powershell
puppet agent --test
```

Expected output:
```
Info: Applying configuration version '1718000001'
Notice: /Stage[main]/Main/Node[win01.example.com]/File[C:/ProgramData/PuppetTest]/ensure: created
Notice: /Stage[main]/Main/Node[win01.example.com]/File[C:/ProgramData/PuppetTest/managed.txt]/ensure: defined content ...
Notice: /Stage[main]/Main/Node[win01.example.com]/Registry_key[HKLM\SOFTWARE\PuppetTest]/ensure: created
Notice: /Stage[main]/Main/Node[win01.example.com]/Registry_value[HKLM\SOFTWARE\PuppetTest\ManagedBy]/ensure: created
Notice: Applied catalog in 2.14 seconds
```

### Step 4 — Verify the results

```powershell
# Check the file
Get-Content 'C:\ProgramData\PuppetTest\managed.txt'

# Check the registry
Get-ItemProperty -Path 'HKLM:\SOFTWARE\PuppetTest'
# ManagedBy should be "Puppet"
```

---

## Part 7 — Start the Agent Service (5 min)

Now that everything works, configure the agent to run as a service:

```powershell
# Start the Puppet agent service
Start-Service puppet

# Verify it's running
Get-Service puppet | Select-Object Name, Status, StartType

# Configure it to start automatically at boot
Set-Service puppet -StartupType Automatic

# Verify the service is configured correctly
Get-Service puppet | Select-Object Name, Status, StartType
```

The agent will now:
- Run every 30 minutes (as configured by `runinterval` in `puppet.conf`)
- Start automatically after reboot
- Re-enforce the catalog on every run (idempotent)

---

## Part 8 — Verify the Node in PuppetDB (Optional, 5 min)

If your Puppet Server has PuppetDB configured:

```bash
# On the Puppet Server — query PuppetDB for the Windows node
curl -s 'http://localhost:8080/pdb/query/v4/nodes' | python3 -m json.tool | grep -A5 'win01'

# Query the most recent facts from the Windows node
curl -s "http://localhost:8080/pdb/query/v4/facts?query=[\"=\",\"certname\",\"win01.example.com\"]" \
  | python3 -m json.tool | head -80
```

---

## Troubleshooting

### "certificate verify failed" or "SSL error"

```powershell
# Clean the SSL directory and re-bootstrap
puppet ssl clean win01.example.com   # run on the agent

# On the Puppet Server, revoke and re-sign
sudo puppetserver ca clean --certname win01.example.com
```

Then re-run `puppet agent --test` on the Windows node.

### "Could not retrieve catalog" — connection refused

```powershell
# Verify network path
Test-NetConnection -ComputerName puppet.example.com -Port 8140

# Check puppet.conf has the right server value
puppet config print server
```

### Firewall blocking port 8140

```powershell
# Check Windows Firewall (usually not the issue on outbound port 8140)
Get-NetFirewallRule | Where-Object { $_.DisplayName -like '*8140*' }

# Add outbound rule if needed (rare — Windows allows all outbound by default)
New-NetFirewallRule -DisplayName 'Puppet Agent Outbound' `
  -Direction Outbound -Protocol TCP -RemotePort 8140 -Action Allow
```

### "Could not find class registry_key"

The `puppetlabs-registry` module is not installed on the server:

```bash
# On the Puppet Server
sudo puppet module install puppetlabs-registry
sudo systemctl restart puppetserver
```

---

## Summary

You have:
1. Prepared name resolution between the Windows node and Puppet Server
2. Installed `puppet-agent` silently with MSI properties
3. Reviewed and understood the Windows configuration file layout
4. Submitted a Certificate Signing Request and signed it on the server
5. Applied your first Windows-targeted catalog
6. Verified file and registry changes were applied
7. Started the agent as a Windows service

**Continue to Exercise 2** to explore the full range of Windows resources: Chocolatey packages, registry management, services, file ACLs, and more.
