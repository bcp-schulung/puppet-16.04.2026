# Exercise 3 — Facts, Custom Facts, and Templates

**Estimated time:** 60–75 minutes

## Objective

Explore the `$facts` hash, write a custom Ruby fact and an external fact, then use both ERB and EPP templates to generate configuration files whose content depends on system facts. You will build a practical `ntp` class that configures the NTP client correctly regardless of the underlying Linux distribution.

---

## Prerequisites

- Day 1 exercises completed — Puppet Server, Agent, and the `webstack` module are working
- SSH access to both the server and agent machines

---

## Part 1 — Explore the `$facts` Hash (10 min)

### Step 1 — List all top-level facts on the agent

```bash
/opt/puppetlabs/bin/facter
```

The output is a long YAML-formatted dump of every fact Facter knows about this node.

### Step 2 — Query specific facts

```bash
# Operating system details
/opt/puppetlabs/bin/facter os

# Network information
/opt/puppetlabs/bin/facter networking

# CPU and memory
/opt/puppetlabs/bin/facter processors
/opt/puppetlabs/bin/facter memory

# Virtualisation
/opt/puppetlabs/bin/facter virtual
```

### Step 3 — Query nested facts

Facter uses `.` as the path separator for structured facts:

```bash
/opt/puppetlabs/bin/facter os.family
/opt/puppetlabs/bin/facter os.release.full
/opt/puppetlabs/bin/facter networking.fqdn
/opt/puppetlabs/bin/facter processors.count
```

### Step 4 — Output as JSON

```bash
/opt/puppetlabs/bin/facter -j | python3 -m json.tool | head -40
```

---

## Part 2 — Use Facts in a Manifest (10 min)

Write a manifest that sets different NTP pool servers based on the OS family:

Create `/etc/puppetlabs/code/environments/production/modules/webstack/manifests/clock.pp`:

```puppet
# @summary Manages the system clock and NTP client.
class webstack::clock {

  # Select the correct NTP package name for this OS family
  $ntp_package = $facts['os']['family'] ? {
    'Debian' => 'ntp',
    'RedHat' => 'chrony',
    default  => 'ntp',
  }

  # Select NTP service name
  $ntp_service = $facts['os']['family'] ? {
    'Debian' => 'ntp',
    'RedHat' => 'chronyd',
    default  => 'ntp',
  }

  # Select NTP config file path
  $ntp_conf = $facts['os']['family'] ? {
    'Debian' => '/etc/ntp.conf',
    'RedHat' => '/etc/chrony.conf',
    default  => '/etc/ntp.conf',
  }

  # Build a descriptive message using multiple facts
  $node_info = "# Managed by Puppet\n# Host: ${facts['networking']['fqdn']}\n# OS: ${facts['os']['name']} ${facts['os']['release']['full']}\n# CPU cores: ${facts['processors']['count']}\n"

  package { $ntp_package:
    ensure => installed,
  }

  file { $ntp_conf:
    ensure  => file,
    content => "${node_info}\nserver 0.pool.ntp.org iburst\nserver 1.pool.ntp.org iburst\nserver 2.pool.ntp.org iburst\n",
    require => Package[$ntp_package],
    notify  => Service[$ntp_service],
  }

  service { $ntp_service:
    ensure  => running,
    enable  => true,
    require => Package[$ntp_package],
  }
}
```

Add `include webstack::clock` to the node block in `site.pp`, apply, and verify:

```bash
sudo puppet agent --test
cat /etc/ntp.conf   # or /etc/chrony.conf on RedHat
```

---

## Part 3 — Write a Custom Ruby Fact (15 min)

We will create a custom fact that reports whether the `nginx` process is currently running.

### Step 1 — Create the fact file

```bash
mkdir -p /etc/puppetlabs/code/environments/production/modules/webstack/lib/facter
```

Create `/etc/puppetlabs/code/environments/production/modules/webstack/lib/facter/nginx_running.rb`:

```ruby
# Custom fact: reports whether nginx is currently running as a process
Facter.add('nginx_running') do
  setcode do
    # Use the systemctl command to check status; returns true/false
    Facter::Core::Execution.which('systemctl') &&
      Facter::Core::Execution.execute('systemctl is-active nginx 2>/dev/null').strip == 'active'
  end
end
```

### Step 2 — Create a structured fact reporting nginx details

Create `/etc/puppetlabs/code/environments/production/modules/webstack/lib/facter/nginx_info.rb`:

```ruby
Facter.add('nginx_info') do
  setcode do
    nginx_bin = Facter::Core::Execution.which('nginx')

    if nginx_bin
      version_output = Facter::Core::Execution.execute("#{nginx_bin} -v 2>&1").strip
      version_match  = version_output.match(/nginx\/(\d+\.\d+\.\d+)/)
      version        = version_match ? version_match[1] : 'unknown'

      {
        'present' => true,
        'version' => version,
        'binary'  => nginx_bin,
      }
    else
      { 'present' => false }
    end
  end
end
```

### Step 3 — Apply and verify

```bash
sudo puppet agent --test   # this triggers pluginsync — facts are copied to the agent
/opt/puppetlabs/bin/facter nginx_running
/opt/puppetlabs/bin/facter nginx_info
```

Expected output:
```
true
{
  binary => "/usr/sbin/nginx",
  present => true,
  version => "1.24.0"
}
```

### Step 4 — Use the custom fact in a manifest

Add this conditional to `webstack::clock` or directly in `site.pp`:

```puppet
if $facts['nginx_running'] {
  notify { 'nginx-status':
    message => "nginx ${facts['nginx_info']['version']} is running on ${facts['networking']['fqdn']}",
  }
}
```

---

## Part 4 — Write an External Fact (5 min)

External facts don't require Ruby — perfect for simple environment metadata.

### Step 1 — Create an external facts directory

```bash
mkdir -p /etc/puppetlabs/code/environments/production/modules/webstack/facts.d
```

### Step 2 — Create a static YAML external fact

Create `/etc/puppetlabs/code/environments/production/modules/webstack/facts.d/datacenter.yaml`:

```yaml
---
datacenter: lab01
rack: A01
environment_tier: training
```

### Step 3 — Apply and verify

```bash
sudo puppet agent --test
/opt/puppetlabs/bin/facter datacenter
/opt/puppetlabs/bin/facter rack
/opt/puppetlabs/bin/facter environment_tier
```

---

## Part 5 — ERB Template (10 min)

We will replace the inline string in `webstack::clock` with a proper ERB template.

### Step 1 — Create the templates directory and an ERB template

```bash
mkdir -p /etc/puppetlabs/code/environments/production/modules/webstack/templates
```

Create `/etc/puppetlabs/code/environments/production/modules/webstack/templates/ntp.conf.erb`:

```erb
# /etc/ntp.conf
# Managed by Puppet - do not edit manually
# Generated: <%= Time.now.strftime('%Y-%m-%d') %>
# Host: <%= @fqdn %>
# OS: <%= @os_name %> <%= @os_release %>
# CPU cores: <%= @cpu_count %>

# Prohibit general access to this time server
restrict default kod nomodify notrap nopeer noquery
restrict -6 default kod nomodify notrap nopeer noquery
restrict 127.0.0.1
restrict ::1

# Time sources
<% @ntp_servers.each do |server| -%>
server <%= server %> iburst
<% end -%>

driftfile /var/lib/ntp/drift
logfile   /var/log/ntp.log
```

### Step 2 — Update the class to use the ERB template

Update `webstack::clock`, replacing the inline `content =>` string with:

```puppet
  # Expose variables needed by the template as local variables
  $fqdn       = $facts['networking']['fqdn']
  $os_name    = $facts['os']['name']
  $os_release = $facts['os']['release']['full']
  $cpu_count  = $facts['processors']['count']
  $ntp_servers = ['0.pool.ntp.org', '1.pool.ntp.org', '2.pool.ntp.org']

  file { $ntp_conf:
    ensure  => file,
    content => template('webstack/ntp.conf.erb'),
    require => Package[$ntp_package],
    notify  => Service[$ntp_service],
  }
```

Apply and inspect the result:

```bash
sudo puppet agent --test
cat /etc/ntp.conf
```

---

## Part 6 — EPP Template (10 min)

Now rewrite the same template in EPP (the modern Puppet-native format).

### Step 1 — Create the EPP template

Create `/etc/puppetlabs/code/environments/production/modules/webstack/templates/ntp.conf.epp`:

```epp
<%- |
  String        $fqdn,
  String        $os_name,
  String        $os_release,
  Integer       $cpu_count,
  Array[String] $ntp_servers,
| -%>
# /etc/ntp.conf
# Managed by Puppet - do not edit manually
# Host: <%= $fqdn %>
# OS: <%= $os_name %> <%= $os_release %>
# CPU cores: <%= $cpu_count %>

restrict default kod nomodify notrap nopeer noquery
restrict 127.0.0.1

# Time sources
<% $ntp_servers.each |$server| { -%>
server <%= $server %> iburst
<% } -%>

driftfile /var/lib/ntp/drift
```

### Step 2 — Switch the class to use epp()

Replace `template('webstack/ntp.conf.erb')` with the EPP call:

```puppet
  content => epp('webstack/ntp.conf.epp', {
    fqdn        => $fqdn,
    os_name     => $os_name,
    os_release  => $os_release,
    cpu_count   => $cpu_count,
    ntp_servers => $ntp_servers,
  }),
```

Apply and verify the output is identical:

```bash
sudo puppet agent --test
cat /etc/ntp.conf
```

---

## Checkpoint Questions

1. What is the difference between how ERB and EPP templates access variables?
2. Why does `epp()` require you to pass the parameters explicitly, while `template()` does not?
3. What happens to fact data between agent runs? Where is it stored on the server?
4. What security advantage do `$trusted` facts provide over regular `$facts`?
5. When would you choose a Ruby custom fact over an external fact, and vice versa?

---

## Stretch Goal

Extend `nginx_info` to also report:
- The number of worker processes (parse `/etc/nginx/nginx.conf` for `worker_processes`)
- Whether the service is enabled for boot (use `systemctl is-enabled nginx`)

Then use this structured fact in a report manifest that writes to `/etc/motd`:

```puppet
$motd = inline_epp(@("EOF")
  System: <%= $facts['networking']['fqdn'] %>
  Nginx:  <%= $facts['nginx_info']['version'] %> (<%= $facts['nginx_running'] ? 'running' : 'stopped' %>)
  OS:     <%= $facts['os']['name'] %> <%= $facts['os']['release']['full'] %>
  | EOF
)

file { '/etc/motd':
  ensure  => file,
  content => $motd,
}
```
