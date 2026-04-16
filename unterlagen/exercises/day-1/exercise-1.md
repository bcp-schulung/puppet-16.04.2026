# Exercise 1 — Install Puppet Server and Agent, Manage Certificates

**Estimated time:** 60–75 minutes

## Objective

Install a Puppet Server and connect a Puppet Agent to it. Sign the agent's certificate, trigger your first managed agent run, and verify that the node is under Puppet control. By the end of this exercise you will understand the full bootstrap flow — from package installation to a signed certificate and a successful catalog application.

---

## Prerequisites

- Two Linux virtual machines (VMs or containers) on the same network:
  - **server**: at least 2 vCPU, 4 GB RAM — will run `puppetserver`
  - **agent**: at least 1 vCPU, 1 GB RAM — will run `puppet-agent`
- OS: Ubuntu 22.04 or Rocky Linux 9 (adjust package manager commands where noted)
- Both machines can resolve each other by hostname (set `/etc/hosts` if DNS is not available)
- Root or `sudo` access on both machines

---

## Part 1 — Prepare Hostnames and Name Resolution (5 min)

### Step 1 — Set hostnames

On the **server**:
```bash
sudo hostnamectl set-hostname puppet.example.com
```

On the **agent**:
```bash
sudo hostnamectl set-hostname agent01.example.com
```

### Step 2 — Ensure both machines can resolve each other

On **both** machines, add entries to `/etc/hosts` (replace IPs with your actual IPs):

```bash
# /etc/hosts — add on BOTH machines
192.168.1.10  puppet.example.com  puppet
192.168.1.20  agent01.example.com agent01
```

Verify from the agent:
```bash
ping -c 2 puppet.example.com
```

> The Puppet agent connects to the hostname `puppet` by default. The entry `puppet.example.com puppet` ensures this short name resolves.

---

## Part 2 — Install the Puppet Server (15 min)

All commands in this section are run on the **server** machine.

### Step 1 — Add the Puppet platform repository

**Ubuntu 22.04:**
```bash
wget https://apt.puppet.com/puppet8-release-jammy.deb
sudo dpkg -i puppet8-release-jammy.deb
sudo apt-get update
```

**Rocky Linux 9:**
```bash
sudo rpm -Uvh https://yum.puppet.com/puppet8-release-el-9.noarch.rpm
sudo dnf makecache
```

### Step 2 — Install puppetserver

**Ubuntu:**
```bash
sudo apt-get install -y puppetserver
```

**Rocky Linux:**
```bash
sudo dnf install -y puppetserver
```

### Step 3 — Tune JVM memory

For a lab environment, reduce the default 2 GB heap to 1 GB:

**Ubuntu** — edit `/etc/default/puppetserver`:
**Rocky** — edit `/etc/sysconfig/puppetserver`:

Find the `JAVA_ARGS` line and change:
```
JAVA_ARGS="-Xms2g -Xmx2g ...
```
to:
```
JAVA_ARGS="-Xms1g -Xmx1g ...
```

### Step 4 — Start and enable the service

```bash
sudo systemctl start puppetserver
sudo systemctl enable puppetserver
sudo systemctl status puppetserver
```

The server takes 30–60 seconds to fully start. Wait until the status shows `active (running)`.

### Step 5 — Verify the server is listening

```bash
sudo ss -tlnp | grep 8140
```

You should see puppetserver (Java) bound to `0.0.0.0:8140`.

---

## Part 3 — Install the Puppet Agent (10 min)

All commands in this section are run on the **agent** machine.

### Step 1 — Add the Puppet platform repository

**Ubuntu 22.04:**
```bash
wget https://apt.puppet.com/puppet8-release-jammy.deb
sudo dpkg -i puppet8-release-jammy.deb
sudo apt-get update
```

**Rocky Linux 9:**
```bash
sudo rpm -Uvh https://yum.puppet.com/puppet8-release-el-9.noarch.rpm
sudo dnf makecache
```

### Step 2 — Install puppet-agent

**Ubuntu:**
```bash
sudo apt-get install -y puppet-agent
```

**Rocky:**
```bash
sudo dnf install -y puppet-agent
```

### Step 3 — Configure the agent

Edit `/etc/puppetlabs/puppet/puppet.conf`:

```ini
[main]
server      = puppet.example.com
environment = production

[agent]
runinterval = 1800
```

### Step 4 — Verify the Facter installation

```bash
/opt/puppetlabs/bin/facter os
/opt/puppetlabs/bin/facter networking.fqdn
```

---

## Part 4 — Certificate Signing (10 min)

### Step 1 — Trigger the first agent run (sends the CSR)

On the **agent**:
```bash
sudo /opt/puppetlabs/bin/puppet agent --test
```

You will see output ending with something like:
```
Info: Creating a new SSL key for agent01.example.com
Info: Caching certificate for ca
Info: csr_attributes file loading from ...
Info: Creating a new SSL certificate request for agent01.example.com
Info: Certificate Request fingerprint (SHA256): AA:BB:CC:...
Exiting; no certificate found and waitforcert is disabled
```

This is **expected** — the agent submitted its CSR and is waiting for it to be signed.

### Step 2 — List pending CSRs on the server

On the **server**:
```bash
sudo /opt/puppetlabs/bin/puppetserver ca list
```

You should see:
```
Requested Certificates:
    agent01.example.com  (SHA256) AA:BB:CC:...
```

### Step 3 — Sign the certificate

```bash
sudo /opt/puppetlabs/bin/puppetserver ca sign --certname agent01.example.com
```

Expected output:
```
Successfully signed certificate request for agent01.example.com
```

### Step 4 — Run the agent again

On the **agent**:
```bash
sudo /opt/puppetlabs/bin/puppet agent --test
```

This time the agent retrieves its signed certificate, downloads the catalog, and applies it. Since `site.pp` is empty, you should see:

```
Info: Using configured environment 'production'
Info: Retrieving pluginfacts
Info: Retrieving plugin
Info: Caching catalog for agent01.example.com
Info: Applying configuration version '...'
Notice: Applied catalog in 0.05 seconds
```

**Success!** The node is now managed by Puppet.

---

## Part 5 — Explore Certificate Management (10 min)

### List all certificates

On the server:
```bash
sudo puppetserver ca list --all
```

The output shows signed certificates, pending requests, and revoked certs.

### Revoke and clean a certificate

Simulate decommissioning:

```bash
# Revoke
sudo puppetserver ca revoke --certname agent01.example.com

# Clean (remove from disk)
sudo puppetserver ca clean --certname agent01.example.com

# On the agent — clean the local cert to allow re-enrolment
sudo puppet ssl clean
```

### Re-enrol

```bash
sudo puppet agent --test   # generates new CSR
# Sign again on the server
sudo puppetserver ca sign --certname agent01.example.com
```

---

## Part 6 — Apply a Simple Manifest (10 min)

Let's put the node under actual configuration management.

### Step 1 — Write a node manifest on the server

Edit `/etc/puppetlabs/code/environments/production/manifests/site.pp`:

```puppet
node 'agent01.example.com' {
  file { '/etc/motd':
    ensure  => file,
    content => "This node is managed by Puppet.\nDo not make manual changes.\n",
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
  }

  package { 'vim':
    ensure => installed,
  }
}
```

### Step 2 — Apply on the agent

```bash
sudo puppet agent --test
```

### Step 3 — Verify

```bash
cat /etc/motd
which vim
```

### Step 4 — Verify idempotency

Run the agent again:
```bash
sudo puppet agent --test
```

The output should show `Applied catalog in X.XX seconds` with **0 changes** — Puppet detected the desired state already matches and made no modifications.

---

## Checkpoint Questions

1. What is the purpose of the CSR/certificate signing step? Why does Puppet require it before an agent can receive a catalog?
2. What file on the agent stores its configuration? What does `runinterval` control?
3. Where does the Puppet Server store signed certificates?
4. What would happen if you ran `puppet agent --test` twice with the same manifest? Why?
5. What is the difference between `puppet agent --test` and `puppet agent --noop`?

---

## Stretch Goal

Configure **policy-based autosigning** for your lab domain so new agents in `*.example.com` are signed automatically:

```bash
# On the server, edit /etc/puppetlabs/puppet/puppet.conf
# Under [server], add:
autosign = /etc/puppetlabs/puppet/autosign.conf
```

```
# /etc/puppetlabs/puppet/autosign.conf
*.example.com
```

```bash
sudo systemctl restart puppetserver
```

Spin up a second agent, run `puppet agent --test` — it should be signed and apply the catalog in one step.
