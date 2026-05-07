# Exercise 5 — Module Structure, Puppet Forge, and r10k

**Estimated time:** 75–90 minutes

## Objective

Build a properly structured Puppet module from scratch using the PDK, consume a Puppet Forge module as a dependency, implement the Roles and Profiles pattern, and deploy everything through a control repository managed by r10k. By the end you will have a complete, version-controlled Puppet infrastructure with environment-based code deployment.

---

## Prerequisites

- Day 1 and Day 2 exercises completed
- Git installed on the Puppet Server: `apt-get install -y git` or `dnf install -y git`
- Internet access from the Puppet Server (for Puppet Forge downloads)
- PDK installed: see https://www.puppet.com/try-puppet/puppet-development-kit/

---

## Part 1 — Install the PDK (5 min)

**Ubuntu:**
```bash
wget https://apt.puppet.com/puppet-tools-release-jammy.deb
sudo dpkg -i puppet-tools-release-jammy.deb
sudo apt-get update && sudo apt-get install -y pdk
```

**Rocky Linux:**
```bash
sudo rpm -Uvh https://yum.puppet.com/puppet-tools-release-el-9.noarch.rpm
sudo dnf install -y pdk
```

Verify:
```bash
pdk --version
```

---

## Part 2 — Create a Module with PDK (15 min)

We will create a `profile` module that implements the Roles and Profiles pattern.

### Step 1 — Scaffold the profile module

```bash
cd /tmp
pdk new module profile \
  --skip-interview \
  --template-url https://github.com/puppetlabs/pdk-templates
```

PDK creates the full directory structure:

```
profile/
├── manifests/
├── spec/
├── data/
├── hiera.yaml
├── metadata.json
├── Gemfile
├── Rakefile
└── README.md
```

### Step 2 — Create the base profile

```bash
cd profile
pdk new class profile::base
```

This creates `manifests/base.pp` with the class stub and `spec/classes/base_spec.rb` with the test stub.

### Step 3 — Write the base profile

Edit `manifests/base.pp`:

```puppet
# @summary Base profile applied to every managed node.
#
# Manages: required packages, NTP, timezone, and the Puppet agent run interval.
#
# All data is supplied via Hiera using the key `profile::base::*`.
#
# @param packages
#   List of packages to ensure are installed on every node.
# @param timezone
#   System timezone.
# @param ntp_servers
#   List of NTP server hostnames.
class profile::base (
  Array[String]  $packages    = [],
  String         $timezone    = 'UTC',
  Array[String]  $ntp_servers = ['pool.ntp.org'],
) {

  # Packages
  package { $packages:
    ensure => installed,
  }

  # Timezone via the timedatectl command
  exec { 'set-timezone':
    command => "/usr/bin/timedatectl set-timezone ${timezone}",
    unless  => "/usr/bin/timedatectl | grep -q 'Time zone: ${timezone}'",
    path    => ['/usr/bin', '/bin'],
  }

  # NTP configuration (simplified inline — use dedicated NTP module in production)
  $ntp_conf_content = $ntp_servers.reduce("") |$memo, $srv| {
    "${memo}server ${srv} iburst\n"
  }

  $ntp_package = $facts['os']['family'] ? {
    'RedHat' => 'chrony',
    default  => 'ntp',
  }

  $ntp_service = $facts['os']['family'] ? {
    'RedHat' => 'chronyd',
    default  => 'ntp',
  }

  package { $ntp_package:
    ensure => installed,
  }

  service { $ntp_service:
    ensure  => running,
    enable  => true,
    require => Package[$ntp_package],
  }
}
```

### Step 4 — Create a webserver profile

```bash
pdk new class profile::webserver
```

Edit `manifests/webserver.pp`:

```puppet
# @summary Webserver profile: installs and configures nginx with vhosts from Hiera.
#
# @param worker_processes
#   Number of nginx worker processes.
# @param vhosts
#   Hash of vhost configurations. Each key is the vhost name;
#   value is a hash passed directly to webstack::vhost.
class profile::webserver (
  Integer       $worker_processes = $facts['processors']['count'],
  Hash          $vhosts           = {},
) {
  include webstack

  # Create vhosts from Hiera data
  $vhosts.each |$name, $config| {
    webstack::vhost { $name:
      * => $config,
    }
  }
}
```

### Step 5 — Create a role

```bash
pdk new class role::webserver
```

Edit `manifests/webserver.pp` (inside the role module or create a separate `role` module):

```puppet
# @summary Webserver role — assigned to nodes serving HTTP traffic.
class role::webserver {
  include profile::base
  include profile::webserver
}
```

---

## Part 3 — Consume a Puppet Forge Module (10 min)

We'll add `puppetlabs-stdlib` as a dependency (it provides useful functions used in many modules).

### Step 1 — Install from the Forge (direct install for now)

```bash
sudo /opt/puppetlabs/bin/puppet module install puppetlabs-stdlib --version 9.4.1 \
  --modulepath /etc/puppetlabs/code/environments/production/modules
```

### Step 2 — Use a stdlib function in the base profile

Add this to `profile::base` to validate the timezone string:

```puppet
  # Validate timezone is a non-empty string (stdlib)
  assert_type(String[1], $timezone) |$expected, $actual| {
    fail("profile::base: timezone must be a non-empty String, got ${actual}")
  }
```

Or use the `validate_legacy` pattern:

```puppet
  unless $timezone =~ /^\w+(\/\w+)?$/ {
    fail("profile::base: invalid timezone '${timezone}'")
  }
```

---

## Part 4 — Create a Control Repository (20 min)

### Step 1 — Initialise a Git repository

```bash
mkdir -p /opt/puppet-control
cd /opt/puppet-control
git init
git checkout -b production
```

### Step 2 — Create the control repo structure

```bash
mkdir -p {manifests,data/{os,nodes},modules/{profile/manifests,role/manifests}}
```

### Step 3 — Create environment.conf

```bash
cat > environment.conf << 'EOF'
modulepath = modules:$basemodulepath
manifest   = manifests/site.pp
EOF
```

### Step 4 — Create hiera.yaml

```bash
cat > hiera.yaml << 'EOF'
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
EOF
```

### Step 5 — Create the Puppetfile

```bash
cat > Puppetfile << 'EOF'
forge "https://forgeapi.puppet.com"

# Core dependencies
mod 'puppetlabs-stdlib',  '9.4.1'
mod 'puppetlabs-ntp',     '10.0.0'

# Internal modules (would point to Git repos in production)
# mod 'myorg-webstack',
#   git: 'git@github.com:myorg/puppet-webstack.git',
#   tag: 'v1.0.0'
EOF
```

### Step 6 — Copy manifests and data

```bash
# site.pp
cat > manifests/site.pp << 'EOF'
node default {
  include role::base
}

node 'agent01.example.com' {
  include role::webserver
}
EOF

# Common Hiera data
cat > data/common.yaml << 'EOF'
---
profile::base::packages:
  - vim
  - curl
  - htop

profile::base::timezone: 'Europe/Berlin'

profile::base::ntp_servers:
  - '0.pool.ntp.org'
  - '1.pool.ntp.org'

profile::webserver::vhosts:
  site-alpha:
    servername: 'alpha.example.com'
    port: 8080
  site-beta:
    servername: 'beta.example.com'
    port: 8081

lookup_options:
  profile::base::packages:
    merge: unique
EOF
```

### Step 7 — Commit everything

```bash
git add .
git commit -m "Initial control repository structure"
```

---

## Part 5 — Install and Configure r10k (10 min)

### Step 1 — Install r10k

```bash
sudo /opt/puppetlabs/puppet/bin/gem install r10k
```

### Step 2 — Create the r10k configuration

```bash
sudo mkdir -p /etc/puppetlabs/r10k

sudo tee /etc/puppetlabs/r10k/r10k.yaml << 'EOF'
---
cachedir: '/var/cache/r10k'

sources:
  control:
    remote: '/opt/puppet-control'
    basedir: '/etc/puppetlabs/code/environments'
EOF
```

> In a real environment, `remote` points to a Git remote (GitHub/GitLab URL). We use a local path for the lab.

### Step 3 — Deploy the production environment

```bash
sudo /opt/puppetlabs/puppet/bin/r10k deploy environment production -pv
```

You should see output like:
```
INFO     -> Deploying environment /etc/puppetlabs/code/environments/production
INFO     -> Environment production is now at ...
INFO     -> Deploying Puppetfile content /etc/puppetlabs/code/environments/production/modules/stdlib
```

### Step 4 — Verify the deployment

```bash
ls /etc/puppetlabs/code/environments/production/modules/
ls /etc/puppetlabs/code/environments/production/data/
```

### Step 5 — Apply on the agent

```bash
sudo puppet agent --test --environment production
```

---

## Part 6 — Feature Branch Workflow (10 min)

### Step 1 — Create a feature branch

```bash
cd /opt/puppet-control
git checkout -b feature-add-redis
```

### Step 2 — Add a Redis profile

```bash
cat > modules/profile/manifests/redis.pp << 'EOF'
class profile::redis (
  Integer $port    = 6379,
  String  $bind    = '127.0.0.1',
  Boolean $persist = false,
) {

  package { 'redis-server':
    ensure => installed,
  }

  file { '/etc/redis/redis.conf':
    ensure  => file,
    content => "port ${port}\nbind ${bind}\n${persist ? { true => 'appendonly yes', false => '# appendonly no' }}\n",
    require => Package['redis-server'],
    notify  => Service['redis-server'],
  }

  service { 'redis-server':
    ensure  => running,
    enable  => true,
    require => Package['redis-server'],
  }
}
EOF

git add modules/profile/manifests/redis.pp
git commit -m "profile::redis: add Redis profile"
```

### Step 3 — Deploy the feature environment

```bash
sudo r10k deploy environment feature_add_redis -pv
```

r10k converts the branch name to a valid Puppet environment name (hyphens → underscores).

### Step 4 — Test the feature environment on the agent

```bash
sudo puppet agent --test --environment feature_add_redis --noop
```

Verify the Redis profile would be applied without touching the production environment.

---

## Checkpoint Questions

1. What is the purpose of the `Puppetfile`? How does it differ from module installation via `puppet module install`?
2. How does r10k convert a Git branch name to a Puppet environment name?
3. What is the relationship between a Git branch and a Puppet environment?
4. Why is a control repository the recommended approach over manually managing modules on the server?
5. What would happen if you deleted a branch from the remote repository and ran `r10k deploy environment -pv`?

---

## Stretch Goal

Set up a simple **post-receive Git hook** to trigger r10k automatically when code is pushed to the control repository:

```bash
cat > /opt/puppet-control/.git/hooks/post-receive << 'EOF'
#!/bin/bash
while read oldrev newrev refname; do
  branch=$(git rev-parse --symbolic --abbrev-ref "$refname")
  echo "Deploying Puppet environment: $branch"
  /opt/puppetlabs/puppet/bin/r10k deploy environment "$branch" -pv
done
EOF
chmod +x /opt/puppet-control/.git/hooks/post-receive
```

Push a change and watch r10k deploy automatically:

```bash
# Make a change to a data file
echo "# test change" >> data/common.yaml
git add data/common.yaml
git commit -m "test: trigger hook"
git push origin production
```
