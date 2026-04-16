# Exercise 2 — Resources, Classes, Conditionals, and Defined Types

**Estimated time:** 60–75 minutes

## Objective

Write a complete, structured manifest that uses Puppet's core language features: multiple resource types with correct ordering, conditional logic based on facts, a reusable class with parameters, and a defined type with multiple instances. By the end of this exercise you will have built a small but production-quality piece of Puppet code.

---

## Prerequisites

- Exercise 1 completed — Puppet Server and Agent are communicating
- Agent can receive and apply a catalog from the server
- SSH or console access to both machines

---

## Part 1 — Create a Module Skeleton (5 min)

We will write a `webstack` module that installs nginx, creates a system user, and manages virtual hosts.

### Step 1 — Create the module directory structure

On the **server**:
```bash
cd /etc/puppetlabs/code/environments/production/modules
mkdir -p webstack/{manifests,files,templates}
```

### Step 2 — Verify the module path

```bash
sudo puppet config print modulepath
```

The path should include the modules directory you just created.

---

## Part 2 — Write the Main Class with Resources and Ordering (20 min)

### Step 1 — Create the main class

Create `/etc/puppetlabs/code/environments/production/modules/webstack/manifests/init.pp`:

```puppet
# @summary Installs and configures the webstack: system user, nginx, and vhosts.
#
# @param user
#   The system user under which web processes run.
# @param manage_firewall
#   Whether to open firewall ports with iptables/firewalld (requires puppetlabs-firewall).
class webstack (
  String  $user            = 'webadmin',
  Integer $uid             = 1500,
  Boolean $manage_firewall = false,
) {

  # 1. System user
  group { $user:
    ensure => present,
    gid    => $uid,
  }

  user { $user:
    ensure     => present,
    uid        => $uid,
    gid        => $user,
    home       => "/home/${user}",
    shell      => '/bin/bash',
    managehome => true,
    require    => Group[$user],
  }

  # 2. Install nginx
  package { 'nginx':
    ensure  => installed,
    require => User[$user],
  }

  # 3. Manage the main config file
  file { '/etc/nginx/nginx.conf':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => "# Managed by Puppet\nworker_processes auto;\nevents { worker_connections 1024; }\nhttp {\n    include /etc/nginx/sites-enabled/*;\n}\n",
    require => Package['nginx'],
    notify  => Service['nginx'],
  }

  # 4. Manage the sites-available and sites-enabled directories
  file { ['/etc/nginx/sites-available', '/etc/nginx/sites-enabled']:
    ensure  => directory,
    owner   => 'root',
    group   => 'root',
    mode    => '0755',
    require => Package['nginx'],
  }

  # 5. Remove the default site
  file { '/etc/nginx/sites-enabled/default':
    ensure  => absent,
    notify  => Service['nginx'],
    require => Package['nginx'],
  }

  # 6. Ensure the service is running
  service { 'nginx':
    ensure  => running,
    enable  => true,
    require => Package['nginx'],
  }
}
```

### Step 2 — Assign the class in site.pp

Edit `/etc/puppetlabs/code/environments/production/manifests/site.pp`:

```puppet
node 'agent01.example.com' {
  include webstack
}
```

### Step 3 — Apply and verify

```bash
# On the agent
sudo puppet agent --test
```

Check:
```bash
systemctl status nginx
id webadmin
ls -la /etc/nginx/
```

---

## Part 3 — Add Conditional Logic Based on Facts (15 min)

### Step 1 — Extend the class with OS-conditional package names

Update `init.pp` to handle differences between Debian and RedHat families. Add this block **before** the `package` resource:

```puppet
  # OS-family-specific settings
  case $facts['os']['family'] {
    'Debian': {
      $nginx_package = 'nginx'
      $nginx_service = 'nginx'
      $www_user      = 'www-data'
    }
    'RedHat': {
      $nginx_package = 'nginx'
      $nginx_service = 'nginx'
      $www_user      = 'nginx'
    }
    default: {
      fail("webstack module is not supported on OS family '${facts['os']['family']}'")
    }
  }
```

Then update the package resource to use `$nginx_package` and the service resource to use `$nginx_service`.

### Step 2 — Add a conditional for the firewall

Insert this block at the end of the class body:

```puppet
  # Open HTTP port if requested
  if $manage_firewall {
    exec { 'open-http-port':
      command => '/usr/sbin/ufw allow 80/tcp',
      unless  => '/usr/sbin/ufw status | grep -q "80/tcp.*ALLOW"',
      path    => ['/usr/sbin', '/usr/bin', '/bin'],
    }
  }
```

### Step 3 — Test the conditional

```bash
# On the agent — noop to preview
sudo puppet agent --test --noop
```

The firewall exec should **not** appear since `$manage_firewall` defaults to `false`.

Now edit `site.pp` to pass `manage_firewall => true`:

```puppet
node 'agent01.example.com' {
  class { 'webstack':
    manage_firewall => true,
  }
}
```

Run the agent again — the exec should now appear in the output.

---

## Part 4 — Create a Defined Type for Virtual Hosts (20 min)

### Step 1 — Write the defined type

Create `/etc/puppetlabs/code/environments/production/modules/webstack/manifests/vhost.pp`:

```puppet
# @summary Creates an nginx virtual host configuration.
#
# @param servername
#   The primary server name (ServerName).
# @param document_root
#   The document root directory. Defaults to /var/www/<title>.
# @param port
#   The port to listen on. Must be between 1 and 65535.
# @param ensure
#   Whether the vhost should be present or absent.
define webstack::vhost (
  String            $servername,
  String            $document_root = "/var/www/${title}",
  Integer[1, 65535] $port          = 80,
  Enum['present', 'absent'] $ensure = 'present',
) {

  $config_ensure = $ensure ? {
    'present' => 'file',
    'absent'  => 'absent',
  }

  # Ensure the document root exists
  if $ensure == 'present' {
    file { $document_root:
      ensure => directory,
      owner  => 'webadmin',
      group  => 'webadmin',
      mode   => '0755',
    }

    file { "${document_root}/index.html":
      ensure  => file,
      content => "<h1>Welcome to ${servername}</h1>\n<p>Managed by Puppet.</p>\n",
      owner   => 'webadmin',
      group   => 'webadmin',
      mode    => '0644',
      require => File[$document_root],
    }
  }

  # Virtual host config
  file { "/etc/nginx/sites-available/${title}":
    ensure  => $config_ensure,
    content => "server {\n    listen ${port};\n    server_name ${servername};\n    root ${document_root};\n    index index.html;\n}\n",
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    require => Package['nginx'],
    notify  => Service['nginx'],
  }

  # Enable by symlinking to sites-enabled
  file { "/etc/nginx/sites-enabled/${title}":
    ensure  => $ensure ? { 'present' => 'link', 'absent' => 'absent' },
    target  => "/etc/nginx/sites-available/${title}",
    require => File["/etc/nginx/sites-available/${title}"],
    notify  => Service['nginx'],
  }
}
```

### Step 2 — Declare multiple vhost instances in site.pp

```puppet
node 'agent01.example.com' {
  include webstack

  webstack::vhost { 'site-alpha':
    servername => 'alpha.example.com',
    port       => 8080,
  }

  webstack::vhost { 'site-beta':
    servername    => 'beta.example.com',
    document_root => '/var/www/beta',
    port          => 8081,
  }
}
```

### Step 3 — Apply and verify

```bash
sudo puppet agent --test
```

Check:
```bash
ls /etc/nginx/sites-available/
ls /etc/nginx/sites-enabled/
ls /var/www/
curl -s http://localhost:8080
curl -s http://localhost:8081
```

---

## Part 5 — Verify Idempotency and Test Noop (5 min)

### Run the agent twice

```bash
sudo puppet agent --test   # should show some changes
sudo puppet agent --test   # should show 0 changes — "Applied catalog in X.XX seconds"
```

### Test a change in noop mode

Edit the `site-beta` vhost block in `site.pp`, change the port to `9090`, then:

```bash
sudo puppet agent --test --noop
```

You should see `Would have changed ...` without applying. Switch back `--noop` and apply for real.

### Remove a vhost

In `site.pp`, remove the `site-beta` block entirely, then:

```bash
sudo puppet agent --test
```

Observe that Puppet does **not** remove the created files. This is expected — Puppet only manages what you declare. To explicitly remove, set `ensure => absent` first.

---

## Checkpoint Questions

1. Why must `Group['webadmin']` be declared before `User['webadmin']`? What happens if you remove the `require`?
2. What is the difference between `notify` and `require`? When does nginx actually restart?
3. Why is a defined type better than a class for managing multiple virtual hosts?
4. What does `Integer[1, 65535]` in a parameter declaration do? Try passing `port => 99999` — what error do you get?
5. Can you declare `webstack::vhost { 'site-alpha': ... }` twice with different parameters? What happens?

---

## Stretch Goal

Extend `webstack::vhost` to accept an `ssl` Boolean parameter. When `true`:
- Listen on `443` instead of (or in addition to) the HTTP port
- Add `ssl_certificate` and `ssl_certificate_key` paths as required String parameters
- The SSL paths should resolve to files managed by a separate `file` resource

The goal is to practise type constraints and conditional resource declarations within a defined type.
