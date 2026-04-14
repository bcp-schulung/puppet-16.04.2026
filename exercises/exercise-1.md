# Exercise 1: Puppet Server Setup and Node Management

## Overview

In this exercise you will install and configure **Puppet Server** on your VSCodium VM. You will then connect two managed nodes — a **DB VM** and an **nginx VM** — to your Puppet Server and use Puppet manifests to automate the installation of software on each node.

**Goals:**
- Install Puppet Server on your VSCodium VM
- Install the Puppet agent on both managed nodes and sign their certificates
- Write a Puppet manifest that installs **PostgreSQL** on the DB VM
- Write a Puppet manifest that installs **nginx** on the nginx VM
- Apply the manifests and verify the services are running

---

## Architecture

```
                        +-------------------------+
                        |    Your VSCodium VM     |
                        |  (Puppet Server)        |
                        |                         |
                        |  manifests/             |
                        |    site.pp              |
                        |    nodes/               |
                        |      db.pp    ------+   |
                        |      nginx.pp ---+  |   |
                        +--------+--------+--+---+
                                 |        |  |
              Puppet agent (443) |        |  | Puppet agent (443)
                                 |        |  |
               +-----------------+        +--+------------------+
               |                                                 |
    +----------+----------+                       +-------------+---------+
    |      DB VM          |                       |       nginx VM        |
    |                     |                       |                       |
    |  Puppet agent       |                       |  Puppet agent         |
    |                     |                       |                       |
    |  installs:          |                       |  installs:            |
    |  [ PostgreSQL ]     |                       |  [ nginx ]            |
    +---------------------+                       +-----------------------+
```

---

## How It Works

1. The **Puppet Server** on your VSCodium VM holds all manifests and acts as the source of truth.
2. The **Puppet agents** on the DB and nginx VMs check in with the server periodically (default every 30 minutes) or on demand.
3. The server compiles a **catalog** for each node based on the manifests and sends it back to the agent.
4. Each agent applies the catalog — installing the packages and ensuring the services are enabled and running.

---

## Step 1: Verify Your Puppet Server Is Running

Run this on your Puppet server VM:

```bash
systemctl status puppetserver
```

Check which agents have enrolled and their certificates are signed:

```bash
puppetserver ca list --all
```

You should see your `db-N` and `nginx-N` nodes listed under **Signed Certificates**.

---

## Step 2: Create Your First Manifest

Create the directory structure for the default Puppet environment:

```bash
mkdir -p /etc/puppet/code/environments/production/manifests
```

Create `site.pp` — the main manifest Puppet reads first:

```bash
cat > /etc/puppet/code/environments/production/manifests/site.pp <<'EOF'
node default {
  file { '/root/puppet_works.txt':
    ensure  => file,
    content => "Puppet is managing this node: ${facts['fqdn']}\nLast run: ${facts['system_uptime']['uptime']}\n",
    owner   => 'root',
    mode    => '0644',
  }
}
EOF
```

---

## Step 3: Trigger a Puppet Run on Your Agents

SSH into your DB VM and run:

```bash
puppet agent --test
```

SSH into your nginx VM and run:

```bash
puppet agent --test
```

You should see output like:

```
Notice: Catalog compiled by vm-1.schuling.it-scholar.com
Notice: /Stage[main]/Main/Node[default]/File[/root/puppet_works.txt]/ensure: defined content as ...
Notice: Applied catalog in 0.01 seconds
```

---

## Step 4: Verify the Result

On each agent VM, confirm Puppet created the file:

```bash
cat /root/puppet_works.txt
```

Expected output (example for db-1):

```
Puppet is managing this node: db-1
Last run: 0:05 hours
```

---

## Step 5: Check the Run Report on the Server

The Puppet server stores a report for every agent run. On your Puppet server:

```bash
ls /var/lib/puppetserver/reports/db-1/
```

---

## What's Next

Now that you have confirmed end-to-end connectivity, move on to:

- **Node classification** — use separate `node 'db-1' { }` blocks to apply different resources to different nodes
- **Install packages** — add `package { 'postgresql': ensure => installed }` to the DB node
- **Manage services** — add `service { 'nginx': ensure => running, enable => true }` to the nginx node
- **Modules** — move your code into `/etc/puppet/code/environments/production/modules/` for reusability
