# @summary Manages a Node.js backend application as a systemd service.
#
# @description
# The `backend` class installs Node.js and npm, creates the required system
# user and group, deploys the backend application files into the specified
# directory, generates the `.env` configuration file, executes `npm install`
# when dependencies are missing, and configures a systemd service named
# `nodejs-backend`.
#
# The application service is automatically restarted whenever `index.js`,
# the `.env` file, or the systemd unit file changes.
#
# Database connection parameters and frontend access settings are injected
# into the generated `.env` file using an Embedded Puppet (EPP) template.
#
# @param db_password
#   Password used to authenticate against the PostgreSQL database.
#   This parameter is required.
#
# @param app_dir
#   Root directory where the backend application will be deployed.
#   Default: `/srv/backend`.
#
# @param user
#   Owner of the application files and user used to run the systemd service.
#   The user is automatically created as a system account.
#   Default: `nodejs`.
#
# @param group
#   Group owner of the application files and group used to run the systemd
#   service.
#   The group is automatically created as a system group.
#   Default: `nodejs`.
#
# @param port
#   TCP port on which the backend application will listen.
#   This value is injected into the generated `.env` file.
#   Default: `3001`.
#
# @param db_host
#   Hostname or IP address of the PostgreSQL database server.
#   Default: `localhost`.
#
# @param db_port
#   TCP port of the PostgreSQL database server.
#   Default: `5432`.
#
# @param db_user
#   PostgreSQL username used by the backend application.
#   Default: `postgres`.
#
# @param db_name
#   PostgreSQL database name used by the backend application.
#   Default: `jokes`.
#
# @param frontend_host
#   Hostname or IP address of the frontend allowed to access the backend.
#   This value is injected into the generated `.env` file and is typically
#   used for CORS configuration.
#   Default: `localhost`.
#
# @example Deploy backend with default settings
#   class { 'backend':
#     db_password => 'secret',
#   }
#
# @example Deploy backend with custom database settings
#   class { 'backend':
#     db_password   => 'supersecret',
#     app_dir       => '/opt/backend',
#     port          => 8081,
#     db_host       => 'postgres.internal.example.com',
#     db_port       => 5432,
#     db_user       => 'backend_user',
#     db_name       => 'backenddb',
#     frontend_host => 'frontend.internal.example.com',
#   }
class backend (
  String  $db_password,
  String  $app_dir        = '/srv/backend',
  String  $user           = 'nodejs',
  String  $group          = 'nodejs',
  Integer $port           = 3001,
  String  $db_host        = 'localhost',
  Integer $db_port        = 5432,
  String  $db_user        = 'postgres',
  String  $db_database    = 'jokes',
  String  $frontend_host  = 'localhost'
) {

  stdlib::ensure_packages('nodejs')
  stdlib::ensure_packages('npm')

  group { $group:
    ensure => 'present',
    system => true,
  }

  user { $user:
    ensure => 'present',
    system => true,
    gid    => $group,
  }

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
    source  => 'puppet:///modules/backend/index.js',
    require => File[$app_dir],
    notify  => Service['nodejs-backend'],
  }

  file { "${app_dir}/package.json":
    ensure  => file,
    owner   => $user,
    group   => $group,
    mode    => '0644',
    source  => 'puppet:///modules/backend/package.json',
    require => File[$app_dir],
  }

  file { "${app_dir}/.env":
    ensure  => file,
    owner   => $user,
    group   => $group,
    mode    => '0640',
    content => epp('backend/env.epp', {
      'port'          => $port,
      'db_host'       => $db_host,
      'db_port'       => $db_port,
      'db_user'       => $db_user,
      'db_password'   => $db_password,
      'db_database'   => $db_database,
      'frontend_host' => $frontend_host,
    }),
    require => File[$app_dir],
    notify  => Service['nodejs-backend'],
  }

  exec { 'backend-npm-install':
    command => '/usr/bin/npm install',
    cwd     => $app_dir,
    creates => "${app_dir}/node_modules",
    require => [
      Package['nodejs'],
      Package['npm'],
      File["${app_dir}/package.json"],
    ],
  }

  file { '/etc/systemd/system/nodejs-backend.service':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => epp('backend/nodejs-backend.service.epp', {
      'user'    => $user,
      'group'   => $group,
      'app_dir' => $app_dir,
    }),
    notify  => Exec['backend-systemd-reload'],
  }

  exec { 'backend-systemd-reload':
    command     => '/bin/systemctl daemon-reload',
    refreshonly => true,
    notify      => Service['nodejs-backend'],
  }

  service { 'nodejs-backend':
    ensure  => running,
    enable  => true,
    require => [
      Exec['backend-systemd-reload'],
      Exec['backend-npm-install'],
    ],
  }
}
