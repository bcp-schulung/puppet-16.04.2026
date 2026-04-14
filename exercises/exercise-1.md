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
