# Infrastructure Overview

## Architecture

```
                          Internet / Students
                                  │
              ┌───────────────────┼───────────────────────┐
              │                   │                       │
              ▼                   ▼                       ▼
  server.puppet.it-scholar.com   vm-2..10.puppet.it-scholar.com
       (port 443)                      (port 443)
       code-server                       ttyd
       (VS Code in browser)           (terminal in browser)
              │                                │
              │                                │
              └──────────────┬─────────────────┘
                             │
                   ┌─────────▼──────────┐
                   │   Cloudflare DNS   │
                   │  DNS-01 (certbot)  │
                   │  TLS via Let's     │
                   │  Encrypt wildcard  │
                   └─────────┬──────────┘
                             │
              ───────────────┴───────────────────────────
              Private Network (Hetzner Cloud)
              ───────────────────────────────────────────

  ┌───────────────────────────────────────────────────────────┐
  │  vm-1  178.104.231.239  server.puppet.it-scholar.com      │
  │                                                           │
  │  ┌─────────────────────┐   ┌──────────────────────────┐  │
  │  │  puppetserver 8.4.0 │   │  code-server 4.117.0     │  │
  │  │  (Ubuntu universe)  │   │  user: student           │  │
  │  │                     │   │  :443  (CAP_NET_BIND)    │  │
  │  │  CA: /etc/puppetlabs│   │  TLS: Let's Encrypt      │  │
  │  │   /puppetserver/ca/ │   └──────────────────────────┘  │
  │  │  config: /etc/puppet│                                  │
  │  │  code:  /etc/puppet │   ┌──────────────────────────┐  │
  │  │   /code/environments│   │  puppet-agent 8.10.0     │  │
  │  │  port: 8140         │   │  (Puppetlabs repo)       │  │
  │  └─────────────────────┘   └──────────────────────────┘  │
  └───────────────────────────────────────────────────────────┘
               │ Puppet CA / catalog (port 8140)
               │
  ┌────────────┴───────────────────────────────────────────────┐
  │                Puppet Agents (vm-2 … vm-10)                │
  │                                                            │
  │  vm-2   178.104.233.67    vm-2.puppet.it-scholar.com       │
  │  vm-3   178.104.232.217   vm-3.puppet.it-scholar.com       │
  │  vm-4   178.104.230.126   vm-4.puppet.it-scholar.com       │
  │  vm-5   178.104.233.138   vm-5.puppet.it-scholar.com       │
  │  vm-6   178.104.225.122   vm-6.puppet.it-scholar.com       │
  │  vm-7   178.104.230.104   vm-7.puppet.it-scholar.com       │
  │  vm-8   159.69.111.48     vm-8.puppet.it-scholar.com       │
  │  vm-9   178.104.237.130   vm-9.puppet.it-scholar.com       │
  │  vm-10  159.69.106.167    vm-10.puppet.it-scholar.com      │
  │                                                            │
  │  Each agent runs:                                          │
  │  ┌────────────────────────┐  ┌───────────────────────────┐ │
  │  │ puppet-agent 8.10.0   │  │ ttyd 1.7.7                │ │
  │  │ (Puppetlabs repo)     │  │ :443  TLS Let's Encrypt   │ │
  │  │ /etc/puppetlabs/puppet│  │ --credential root:PASS    │ │
  │  │ /ssl/  (agent certs)  │  │ /bin/bash                 │ │
  │  └────────────────────────┘  └───────────────────────────┘ │
  └────────────────────────────────────────────────────────────┘
```

## TLS / Certificate Flow

```
  Let's Encrypt (ACME DNS-01)
        │
        │  Cloudflare API Token
        │  zone: puppet.it-scholar.com
        ▼
  certbot (python3-certbot-dns-cloudflare)
  /etc/letsencrypt/cloudflare.ini
        │
        ├──▶ /etc/letsencrypt/live/server.puppet.it-scholar.com/
        │        used by: code-server on vm-1
        │
        └──▶ /etc/letsencrypt/live/vm-N.puppet.it-scholar.com/
                 used by: ttyd on vm-2..10

  Puppet mTLS (separate, internal CA):
  vm-1 puppetserver CA ──signs──▶ agent certs (vm-1..10)
  CA stored at: /etc/puppetlabs/puppetserver/ca/
  Agent SSL at: /etc/puppetlabs/puppet/ssl/
```

## Key Software Versions

| Component       | Version  | Package source          |
|-----------------|----------|-------------------------|
| puppetserver    | 8.4.0    | Ubuntu 24.04 universe   |
| puppet-agent    | 8.10.0   | Puppetlabs apt repo     |
| code-server     | 4.117.0  | code-server.dev script  |
| ttyd            | 1.7.7    | GitHub releases binary  |
| certbot         | –        | Ubuntu 24.04 universe   |
| OS              | Ubuntu 24.04 (Noble) | Hetzner Cloud |

## Deployment

```
setup/deploy_all.sh --parallel --verify
```

Phases:
1. **Puppet Server** — install puppetserver, patch JRuby load path, configure, start
2. **TLS (vm-1)** — certbot DNS-01 → cert for `server.puppet.it-scholar.com`
3. **Puppet Agents** — install puppet-agent, configure, enroll (clean stale CA cert first)
4. **code-server** — install, configure, systemd service with CAP_NET_BIND_SERVICE
5. **ttyd** — download binary, systemd service per agent VM
6. **Verify** — HTTP checks + signed cert count
