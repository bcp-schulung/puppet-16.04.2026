# Exercise 4 — Hiera: Data Separation and Hierarchy-Driven Configuration

**Estimated time:** 60–75 minutes

## Objective

Refactor the `webstack` class to read all its configuration from Hiera instead of hardcoded defaults. Set up a multi-level Hiera hierarchy, demonstrate automatic parameter lookup, explore merge strategies, and use `puppet lookup --explain` to trace where values come from. By the end you will understand why Hiera is central to maintainable Puppet infrastructure.

---

## Prerequisites

- Day 1 exercises and Exercise 3 (Day 2) completed
- The `webstack` module exists under `environments/production/modules/webstack`
- Puppet Server and Agent are communicating

---

## Part 1 — Set Up the Hiera Hierarchy (10 min)

### Step 1 — Create the data directory structure

```bash
cd /etc/puppetlabs/code/environments/production
mkdir -p data/{os,nodes}
```

### Step 2 — Create or update the environment-level `hiera.yaml`

Create `/etc/puppetlabs/code/environments/production/hiera.yaml`:

```yaml
---
version: 5

defaults:
  datadir: data
  data_hash: yaml_data

hierarchy:
  - name: "Node-specific data"
    path: "nodes/%{trusted.certname}.yaml"

  - name: "OS family data"
    path: "os/%{facts.os.family}.yaml"

  - name: "Common data"
    path: "common.yaml"
```

### Step 3 — Create the common data file

Create `/etc/puppetlabs/code/environments/production/data/common.yaml`:

```yaml
---
# Common defaults for all nodes

webstack::user: webadmin
webstack::uid: 1500
webstack::manage_firewall: false

webstack::clock::ntp_servers:
  - '0.pool.ntp.org'
  - '1.pool.ntp.org'
  - '2.pool.ntp.org'

profile::base::packages:
  - vim
  - curl
  - htop
  - tree
```

---

## Part 2 — Refactor the Class for Automatic Parameter Lookup (15 min)

With Hiera set up, Puppet can automatically resolve class parameters from Hiera using the key `classname::parameter`.

### Step 1 — Update `webstack/manifests/init.pp`

The class signature stays the same, but the defaults in the Puppet code become the **last resort** — Hiera values take precedence:

```puppet
class webstack (
  String  $user            = 'webadmin',
  Integer $uid             = 1500,
  Boolean $manage_firewall = false,
) {
  # ... class body unchanged ...
}
```

Because the Hiera key `webstack::user` matches the `$user` parameter of class `webstack`, Puppet will automatically supply the Hiera value. The default in the class signature is only used if Hiera has no answer.

### Step 2 — Update `webstack::clock` to use a Hiera-driven parameter

Update the class signature in `clock.pp`:

```puppet
class webstack::clock (
  Array[String] $ntp_servers = ['pool.ntp.org'],
) {
  # ... rest of class body unchanged ...
  # Replace the hardcoded $ntp_servers assignment with the parameter
}
```

The Hiera key `webstack::clock::ntp_servers` will be automatically looked up.

### Step 3 — Apply and verify the lookup works

```bash
sudo puppet agent --test
```

Verify the NTP config contains the pool servers from `common.yaml`.

---

## Part 3 — Add OS-Specific Data (10 min)

### Step 1 — Create an OS family override

Create `/etc/puppetlabs/code/environments/production/data/os/Debian.yaml`:

```yaml
---
# Debian/Ubuntu-specific overrides

webstack::clock::ntp_servers:
  - '0.debian.pool.ntp.org'
  - '1.debian.pool.ntp.org'
  - '2.debian.pool.ntp.org'
  - '3.debian.pool.ntp.org'

profile::base::packages:
  - vim
  - curl
  - htop
  - tree
  - apt-transport-https
```

Create `/etc/puppetlabs/code/environments/production/data/os/RedHat.yaml`:

```yaml
---
# RedHat/Rocky/AlmaLinux-specific overrides

webstack::clock::ntp_servers:
  - '0.rhel.pool.ntp.org'
  - '1.rhel.pool.ntp.org'

profile::base::packages:
  - vim
  - curl
  - htop
  - tree
  - bash-completion
```

### Step 2 — Apply and verify

```bash
sudo puppet agent --test
cat /etc/ntp.conf   # or /etc/chrony.conf — should now contain the OS-specific servers
```

### Step 3 — Trace the lookup

On the server, use `puppet lookup` to trace the decision:

```bash
sudo /opt/puppetlabs/bin/puppet lookup webstack::clock::ntp_servers \
  --node agent01.example.com \
  --explain \
  --environment production
```

Read the output carefully. It shows each level of the hierarchy searched and where the value was found.

---

## Part 4 — Create a Node-Specific Override (10 min)

### Step 1 — Create a node data file

Replace `agent01.example.com` with your actual agent hostname:

Create `/etc/puppetlabs/code/environments/production/data/nodes/agent01.example.com.yaml`:

```yaml
---
# Node-specific overrides for agent01.example.com

# This node needs a specific NTP server (e.g., lab NTP appliance)
webstack::clock::ntp_servers:
  - '192.168.1.1'     # lab gateway acts as NTP server
  - '0.pool.ntp.org'  # fallback

# Override the user UID for this specific node
webstack::uid: 1600
```

### Step 2 — Apply and verify

```bash
sudo puppet agent --test
cat /etc/ntp.conf   # should now show 192.168.1.1 as the first server
```

### Step 3 — Run the lookup again

```bash
sudo puppet lookup webstack::clock::ntp_servers \
  --node agent01.example.com \
  --explain \
  --environment production
```

Now the output should show the **node-specific** value being used (the highest-priority level).

---

## Part 5 — Merge Strategies (15 min)

By default Hiera uses the `first` merge strategy — the highest-priority level wins and lower levels are ignored. For **arrays** (like package lists) you often want to **accumulate** values from all levels.

### Step 1 — Observe the default (non-merging) behaviour

Add a `profile::base::packages` key to your node file:

```yaml
# data/nodes/agent01.example.com.yaml
profile::base::packages:
  - jq
```

Run a lookup:

```bash
sudo puppet lookup profile::base::packages \
  --node agent01.example.com \
  --explain \
  --environment production
```

With `first` merge, only `['jq']` is returned — the common and OS packages are ignored.

### Step 2 — Configure `unique` merge in `hiera.yaml`

Add `lookup_options` at the bottom of `hiera.yaml`:

```yaml
# append to hiera.yaml
  - name: "Lookup options"
    data_hash: yaml_data
    path: "common.yaml"

# Add lookup_options key to data/common.yaml:
```

In `data/common.yaml`, add:

```yaml
lookup_options:
  profile::base::packages:
    merge: unique
```

### Step 3 — Run the lookup again

```bash
sudo puppet lookup profile::base::packages \
  --node agent01.example.com \
  --explain \
  --environment production
```

Now the result should **merge all levels** — `jq` from the node file, `apt-transport-https` from Debian, and the common packages, all deduplicated into one array.

---

## Part 6 — Explicit Lookup in a Manifest (5 min)

Sometimes you need Hiera data outside of a class parameter context — use the `lookup()` function:

Add this to `site.pp` inside the node block:

```puppet
node 'agent01.example.com' {
  include webstack
  include webstack::clock

  # Explicit lookup with type validation and default
  $base_pkgs = lookup('profile::base::packages', Array[String], 'unique', ['vim'])

  package { $base_pkgs:
    ensure => installed,
  }

  # Lookup with a default fallback
  $log_level = lookup('webstack::log_level', Optional[String], 'first', undef)
  if $log_level {
    notify { "log-level": message => "Log level: ${log_level}" }
  }
}
```

Apply:

```bash
sudo puppet agent --test
```

---

## Checkpoint Questions

1. What is the key naming convention for automatic parameter lookup? Give an example for class `profile::nginx` parameter `$worker_processes`.
2. What happens if a key is present in both `data/os/Debian.yaml` and `data/common.yaml`? Which wins with `first` merge? With `unique` merge?
3. What is the purpose of `lookup_options` in `hiera.yaml`?
4. Why should you prefer Hiera data over hardcoded defaults in class parameters?
5. What does `puppet lookup --explain` tell you that a normal `puppet lookup` does not?

---

## Stretch Goal — eyaml for Secrets

Install and configure `hiera-eyaml` to encrypt sensitive values:

```bash
# On the Puppet Server
/opt/puppetlabs/puppet/bin/gem install hiera-eyaml
cd /etc/puppetlabs/puppet/ssl
eyaml createkeys
```

Update `hiera.yaml` to use the eyaml backend for the common level:

```yaml
  - name: "Common data (encrypted)"
    lookup_key: eyaml_lookup_key
    path: "common.yaml"
    options:
      pkcs7_private_key: /etc/puppetlabs/puppet/ssl/keys/private_key.pkcs7.pem
      pkcs7_public_key:  /etc/puppetlabs/puppet/ssl/keys/public_key.pkcs7.pem
```

Encrypt a test secret:

```bash
eyaml encrypt -s 'my-database-password'
```

Add the resulting `ENC[...]` string to `common.yaml`:

```yaml
myapp::db_password: ENC[PKCS7,MIIBeQ...]
```

Verify it decrypts transparently:

```bash
puppet lookup myapp::db_password --node agent01.example.com --explain
```
