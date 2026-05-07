# Exercise 6 — Testing Puppet Modules with rspec-puppet

**Estimated time:** 60–75 minutes

## Objective

Write unit tests for the `webstack` module using rspec-puppet. Validate that the catalog compiles correctly, contains the expected resources and relationships, and rejects invalid parameter input. Run tests with the PDK and integrate style checks with puppet-lint. By the end of this exercise you will have a tested, lintable module that you can confidently commit and deploy.

---

## Prerequisites

- Day 1–3 exercises completed
- PDK installed on the development machine (can be a laptop or the Puppet Server)
- The `webstack` module exists with `manifests/init.pp`, `manifests/vhost.pp`, and `manifests/clock.pp`

---

## Part 1 — Prepare the Module for Testing (10 min)

If you created the `webstack` module manually (without PDK), you need to add the testing infrastructure.

### Step 1 — Move to the module directory

```bash
cd /etc/puppetlabs/code/environments/production/modules/webstack
```

### Step 2 — Create the PDK testing files

Create `Gemfile`:

```ruby
# Gemfile
source 'https://rubygems.org'

puppet_version = ENV['PUPPET_VERSION'] || '~> 8.0'
gem 'puppet',                   puppet_version
gem 'puppetlabs_spec_helper',   '>= 7.0',  '< 8.0'
gem 'rspec-puppet',             '>= 4.0',  '< 5.0'
gem 'rspec-puppet-facts',       '>= 4.0',  '< 5.0'
gem 'puppet-lint',              '>= 4.0',  '< 5.0'
gem 'rake'
```

Create `Rakefile`:

```ruby
# Rakefile
require 'puppetlabs_spec_helper/rake_tasks'
require 'puppet-lint/tasks/puppet-lint'

PuppetLint.configuration.send(:disable_140chars_check)
PuppetLint.configuration.log_format = '%{path}:%{linenumber}:%{check}:%{KIND}:%{message}'
```

Create `spec/spec_helper.rb`:

```ruby
# spec/spec_helper.rb
require 'puppetlabs_spec_helper/module_spec_helper'
require 'rspec-puppet-facts'

include RspecPuppetFacts

RSpec.configure do |c|
  c.before(:each) do
    Puppet.settings[:strict] = :warning
  end
end
```

Create `metadata.json` if it doesn't exist:

```json
{
  "name": "training-webstack",
  "version": "0.1.0",
  "author": "training",
  "license": "Apache-2.0",
  "summary": "Webstack training module",
  "source": "",
  "dependencies": [],
  "requirements": [
    { "name": "puppet", "version_requirement": ">= 7.0.0 < 9.0.0" }
  ],
  "operatingsystem_support": [
    {
      "operatingsystem": "Ubuntu",
      "operatingsystemrelease": ["22.04"]
    },
    {
      "operatingsystem": "RedHat",
      "operatingsystemrelease": ["9"]
    }
  ]
}
```

### Step 3 — Install gems

```bash
bundle install
```

---

## Part 2 — Write Tests for the Main Class (20 min)

Create `spec/classes/init_spec.rb`:

```ruby
# spec/classes/init_spec.rb
require 'spec_helper'

describe 'webstack' do
  # Test against all OS/version combinations in metadata.json
  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) { os_facts }

      # --- Basic compilation ---
      context 'with default parameters' do
        it { is_expected.to compile.with_all_deps }
      end

      # --- User and group management ---
      context 'user and group resources' do
        it {
          is_expected.to contain_group('webadmin')
            .with_ensure('present')
            .with_gid(1500)
        }

        it {
          is_expected.to contain_user('webadmin')
            .with_ensure('present')
            .with_uid(1500)
            .with_shell('/bin/bash')
            .with_managehome(true)
            .that_requires('Group[webadmin]')
        }
      end

      # --- nginx package and service ---
      context 'nginx installation' do
        it { is_expected.to contain_package('nginx').with_ensure('installed') }
        it {
          is_expected.to contain_service('nginx')
            .with_ensure('running')
            .with_enable(true)
        }
      end

      # --- Config file ---
      context 'nginx config file' do
        it {
          is_expected.to contain_file('/etc/nginx/nginx.conf')
            .with_ensure('file')
            .with_owner('root')
            .with_mode('0644')
            .that_notifies('Service[nginx]')
            .that_requires('Package[nginx]')
        }
      end

      # --- Sites directories ---
      context 'nginx directories' do
        ['/etc/nginx/sites-available', '/etc/nginx/sites-enabled'].each do |dir|
          it { is_expected.to contain_file(dir).with_ensure('directory') }
        end
      end

      # --- Default site removal ---
      context 'default site' do
        it {
          is_expected.to contain_file('/etc/nginx/sites-enabled/default')
            .with_ensure('absent')
        }
      end
    end
  end

  # --- Parameter overrides ---
  context 'with custom user' do
    let(:facts) { { os: { family: 'Debian', name: 'Ubuntu', release: { full: '22.04' } } } }
    let(:params) do
      {
        user: 'deploy',
        uid:  2000,
      }
    end

    it { is_expected.to compile.with_all_deps }
    it { is_expected.to contain_user('deploy').with_uid(2000) }
    it { is_expected.to contain_group('deploy').with_gid(2000) }
  end

  # --- Firewall conditional ---
  context 'with manage_firewall => false (default)' do
    let(:facts) { { os: { family: 'Debian', name: 'Ubuntu', release: { full: '22.04' } } } }

    it { is_expected.not_to contain_exec('open-http-port') }
  end

  context 'with manage_firewall => true' do
    let(:facts) { { os: { family: 'Debian', name: 'Ubuntu', release: { full: '22.04' } } } }
    let(:params) { { manage_firewall: true } }

    it { is_expected.to contain_exec('open-http-port') }
  end
end
```

### Run the tests

```bash
bundle exec rake spec
```

All tests should pass. Study the output — each example is reported as `passed` or `failed`.

---

## Part 3 — Write Tests for the Defined Type (15 min)

Create `spec/defines/vhost_spec.rb`:

```ruby
# spec/defines/vhost_spec.rb
require 'spec_helper'

describe 'webstack::vhost' do
  let(:pre_condition) { "class {'webstack': }" }
  let(:facts) do
    {
      os: { family: 'Debian', name: 'Ubuntu', release: { full: '22.04' } },
    }
  end

  # Each defined type test needs a title
  let(:title) { 'my-site' }

  context 'with minimum required parameters' do
    let(:params) { { servername: 'www.example.com' } }

    it { is_expected.to compile.with_all_deps }

    it {
      is_expected.to contain_file('/etc/nginx/sites-available/my-site')
        .with_ensure('file')
        .with_owner('root')
        .with_mode('0644')
        .that_notifies('Service[nginx]')
    }

    it {
      is_expected.to contain_file('/etc/nginx/sites-enabled/my-site')
        .with_ensure('link')
        .with_target('/etc/nginx/sites-available/my-site')
    }

    it {
      is_expected.to contain_file('/var/www/my-site')
        .with_ensure('directory')
        .with_owner('webadmin')
    }
  end

  context 'with custom document root and port' do
    let(:params) do
      {
        servername:    'custom.example.com',
        document_root: '/opt/myapp/public',
        port:          8443,
      }
    end

    it { is_expected.to compile.with_all_deps }

    it {
      is_expected.to contain_file('/etc/nginx/sites-available/my-site')
        .with_content(/listen 8443/)
        .with_content(/root \/opt\/myapp\/public/)
    }
  end

  context 'with ensure => absent' do
    let(:params) do
      {
        servername: 'www.example.com',
        ensure:     'absent',
      }
    end

    it { is_expected.to compile.with_all_deps }

    it {
      is_expected.to contain_file('/etc/nginx/sites-available/my-site')
        .with_ensure('absent')
    }

    it {
      is_expected.to contain_file('/etc/nginx/sites-enabled/my-site')
        .with_ensure('absent')
    }

    it {
      is_expected.not_to contain_file('/var/www/my-site')
    }
  end

  # --- Type validation ---
  context 'with invalid port' do
    let(:params) { { servername: 'www.example.com', port: 99_999 } }

    it {
      is_expected.to compile
        .and_raise_error(/expects an Integer\[1, 65535\]/)
    }
  end

  context 'with missing servername' do
    let(:params) { {} }

    it {
      is_expected.to compile
        .and_raise_error(/expects a value for parameter 'servername'/)
    }
  end
end
```

```bash
bundle exec rake spec
```

---

## Part 4 — Test Resource Relationships (10 min)

Add relationship tests to the webstack class spec:

```ruby
  context 'resource ordering chain' do
    let(:facts) { { os: { family: 'Debian', name: 'Ubuntu', release: { full: '22.04' } } } }

    it 'config file requires package' do
      is_expected.to contain_file('/etc/nginx/nginx.conf')
        .that_requires('Package[nginx]')
    end

    it 'service requires package' do
      is_expected.to contain_service('nginx')
        .that_requires('Package[nginx]')
    end

    it 'config file notifies service' do
      is_expected.to contain_file('/etc/nginx/nginx.conf')
        .that_notifies('Service[nginx]')
    end

    it 'package requires user' do
      is_expected.to contain_package('nginx')
        .that_requires("User[webadmin]")
    end
  end
```

These assertions verify that the **dependency graph in the catalog** is correct, not just that the resources exist.

---

## Part 5 — puppet-lint Style Checks (5 min)

### Step 1 — Run puppet-lint

```bash
bundle exec puppet-lint manifests/
```

### Step 2 — Fix reported issues

Common issues you might see:

| Issue | Fix |
|---|---|
| `double quoted string containing no variables` | Change `"string"` to `'string'` |
| `arrow not aligned` | Align all `=>` within a resource block |
| `trailing whitespace` | Remove trailing spaces |
| `variable not enclosed in braces` | Change `"$var"` to `"${var}"` |

### Step 3 — Auto-fix where possible

```bash
bundle exec puppet-lint --fix manifests/init.pp
```

> Some issues require manual correction. `--fix` handles whitespace, quoting, and arrow alignment automatically.

### Step 4 — Run all checks together

```bash
bundle exec rake validate lint spec
```

This mirrors what a CI pipeline would run on every push.

---

## Part 6 — Validate Catalog Compilation via puppet parser (5 min)

For quick syntax checks without running full specs:

```bash
# Check syntax of a single manifest
puppet parser validate manifests/init.pp

# Check an entire module
puppet parser validate manifests/

# Check with strict mode
puppet parser validate --strict-variables manifests/
```

---

## Checkpoint Questions

1. What does `compile.with_all_deps` test that `compile` alone does not?
2. Why do we use `let(:pre_condition)` in the defined type spec?
3. What is the difference between `contain_file(...).with_ensure(...)` and `contain_file(...)` alone?
4. rspec-puppet tests the catalog in memory — what can they NOT verify?
5. When would you add an acceptance test, and what tool would you use?

---

## Stretch Goal — Test Coverage and CI

### Step 1 — Generate a test coverage report

```bash
COVERAGE=yes bundle exec rake spec
```

Look for the coverage summary at the bottom. Aim for 100% resource coverage.

### Step 2 — Add a GitHub Actions CI workflow

If you moved the module to a Git repository, add `.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: ["**"]
  pull_request:
    branches: [main, production]

jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        puppet: ["~> 7.0", "~> 8.0"]

    steps:
      - uses: actions/checkout@v4

      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: "3.1"
          bundler-cache: true

      - name: Set Puppet version
        run: echo "PUPPET_VERSION=${{ matrix.puppet }}" >> $GITHUB_ENV

      - name: Validate
        run: bundle exec rake validate

      - name: Lint
        run: bundle exec rake lint

      - name: Unit tests
        run: bundle exec rake spec
```

This runs on every pull request against both Puppet 7 and 8, catching regressions before they reach production.
