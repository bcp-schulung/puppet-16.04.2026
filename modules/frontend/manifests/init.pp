# @summary Manages a Node.js frontend application as a systemd service.
#
# @description
# The `frontend` class installs Node.js and npm, deploys the frontend
# application files into the specified directory, generates the `.env`
# configuration file, executes `npm install` when dependencies are missing,
# and configures a systemd service named `nodejs-frontend`.
#
# The application service is automatically restarted whenever `index.js`,
# `public/index.html`, the `.env` file, or the systemd unit file changes.
#
# @param app_dir
#   Root directory where the frontend application will be deployed.
#   Default: `/srv/frontend`.
#
# @param user
#   Owner of the application files and user used to run the systemd service.
#   Default: `nodejs`.
#
# @param group
#   Group owner of the application files and group used to run the systemd
#   service.
#   Default: `nodejs`.
#
# @param port
#   TCP port on which the frontend application will listen.
#   This value is injected into the generated `.env` file.
#   Default: `3000`.
#
# @param backend_host
#   Hostname or IP address of the backend service used by the frontend.
#   This value is injected into the generated `.env` file.
#   Default: `localhost`.
#
# @example Deploy frontend with default settings
#   include frontend
#
# @example Deploy frontend with custom parameters
#   class { 'frontend':
#     app_dir      => '/opt/frontend',
#     user         => 'frontend',
#     group        => 'frontend',
#     port         => 8080,
#     backend_host => 'api.internal.example.com',
#   }
class frontend (
  String  $app_dir      = '/srv/frontend',
  String  $user         = 'nodejs',
  String  $group        = 'nodejs',
  Integer $port         = 3000,
  String  $backend_host = 'localhost',
) {

  stdlib::ensure_packages('nodejs')
  stdlib::ensure_packages('npm')

  file { $app_dir:
    ensure  => directory,
    owner   => $user,
    group   => $group,
    mode    => '0755',
    recurse => true,
    purge   => true,
    force   => true,
    ignore  => ['node_modules'],
    require => Package['nodejs'],
  }

  file { "${app_dir}/index.js":
    ensure  => file,
    owner   => $user,
    group   => $group,
    mode    => '0644',
    source  => 'puppet:///modules/frontend/index.js',
    require => File[$app_dir],
    notify  => Service['nodejs-frontend'],
  }

  file { "${app_dir}/package.json":
    ensure  => file,
    owner   => $user,
    group   => $group,
    mode    => '0644',
    source  => 'puppet:///modules/frontend/package.json',
    require => File[$app_dir],
  }

  file { "${app_dir}/public":
    ensure  => directory,
    owner   => $user,
    group   => $group,
    mode    => '0755',
    require => File[$app_dir],
  }

  file { "${app_dir}/public/index.html":
    ensure  => file,
    owner   => $user,
    group   => $group,
    mode    => '0644',
    source  => 'puppet:///modules/frontend/public/index.html',
    require => File["${app_dir}/public"],
    notify  => Service['nodejs-frontend'],
  }

  file { "${app_dir}/.env":
    ensure  => file,
    owner   => $user,
    group   => $group,
    mode    => '0640',
    content => epp('frontend/env.epp', {
      'port'         => $port,
      'backend_host' => $backend_host,
    }),
    require => File[$app_dir],
    notify  => Service['nodejs-frontend'],
  }

  exec { 'frontend-npm-install':
    command => '/usr/bin/npm install',
    cwd     => $app_dir,
    creates => "${app_dir}/node_modules",
    require => [
      Package['nodejs'],
      Package['npm'],
      File["${app_dir}/package.json"],
    ],
  }

  file { '/etc/systemd/system/nodejs-frontend.service':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => epp('frontend/nodejs-frontend.service.epp', {
      'user'    => $user,
      'group'   => $group,
      'app_dir' => $app_dir,
    }),
    notify  => Exec['frontend-systemd-reload'],
  }

  exec { 'frontend-systemd-reload':
    command     => '/bin/systemctl daemon-reload',
    refreshonly => true,
    notify      => Service['nodejs-frontend'],
  }

  service { 'nodejs-frontend':
    ensure  => running,
    enable  => true,
    require => [
      Exec['frontend-systemd-reload'],
      Exec['frontend-npm-install'],
    ],
  }
}
