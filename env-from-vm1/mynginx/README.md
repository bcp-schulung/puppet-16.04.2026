# mynginx

A simple Puppet module for Debian and Ubuntu that manages nginx in a reusable way.

## What this module does

- installs the nginx package
- enables and starts the nginx service
- manages the main `/etc/nginx/nginx.conf` file
- installs standard `40x.html` and `50x.html` error pages
- can create a default site automatically
- can point a node to its own document root

## Requirements

- Debian or Ubuntu style nginx layout
- Puppet with module support enabled

## Class usage

### Use the built-in default site

```puppet
class { 'mynginx': }
```

This installs nginx, writes the main configuration, installs the error pages, and creates a default website under `/var/www/mynginx`.

### Use a node-specific content directory

```puppet
node 'nginx-1' {
  class { 'mynginx':
    manage_default_site => false,
  }

  mynginx::site { 'default':
    docroot      => '/srv/my-node-content',
    manage_index => false,
  }
}
```

Use this when the node already has its own website files in a directory and nginx should serve them directly.

### Let Puppet create a sample homepage automatically

```puppet
node 'nginx-1' {
  class { 'mynginx':
    manage_default_site => false,
  }

  mynginx::site { 'default':
    docroot       => '/srv/my-node-content',
    manage_index  => true,
    index_content => "<h1>Hello from Puppet</h1>\n",
  }
}
```

## Parameters

### Class `mynginx`

- `package_name` – package to install, default: `nginx`
- `service_name` – service to manage, default: `nginx`
- `config_path` – main nginx config path, default: `/etc/nginx/nginx.conf`
- `error_pages_dir` – directory for error pages, default: `/usr/share/nginx/html`
- `manage_default_site` – whether the module should create a default site automatically, default: `true`

### Defined type `mynginx::site`

- `docroot` – document root to serve, default: `/var/www/mynginx`
- `server_name` – nginx server name, default: `_`
- `listen_port` – port to listen on, default: `80`
- `default_site` – whether this site is the nginx default site, default: `true`
- `manage_index` – whether Puppet should create an `index.html`, default: `true`
- `index_content` – optional custom content for the generated homepage

## Files in this module

- `manifests/init.pp` – main class
- `manifests/site.pp` – site definition
- `templates/nginx.conf.epp` – nginx main config template
- `templates/site.conf.epp` – nginx site template
- `files/40x.html` – client error page
- `files/50x.html` – server error page

## CI

This repository includes a GitHub Actions workflow that:

- lints Puppet manifests
- validates Puppet and EPP syntax
- checks module metadata
- runs RSpec Puppet tests

The workflow uses Ruby 3.2.
