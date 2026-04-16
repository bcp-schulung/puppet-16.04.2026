# Manages nginx installation, configuration, and default error pages.
class mynginx (
  String  $package_name        = 'nginx',
  String  $service_name        = 'nginx',
  String  $config_path         = '/etc/nginx/nginx.conf',
  String  $error_pages_dir     = '/usr/share/nginx/html',
  Boolean $manage_default_site = true,
) {

  package { $package_name:
    ensure => installed,
  }

  file { [
    '/etc/nginx',
    '/etc/nginx/conf.d',
    '/etc/nginx/sites-available',
    '/etc/nginx/sites-enabled',
    $error_pages_dir,
  ]:
    ensure  => directory,
    owner   => 'root',
    group   => 'root',
    mode    => '0755',
    require => Package[$package_name],
  }

  file { $config_path:
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => epp('mynginx/nginx.conf.epp'),
    require => File['/etc/nginx'],
    notify  => Service[$service_name],
  }

  file { "${error_pages_dir}/40x.html":
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    source  => 'puppet:///modules/mynginx/40x.html',
    require => File[$error_pages_dir],
    notify  => Service[$service_name],
  }

  file { "${error_pages_dir}/50x.html":
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    source  => 'puppet:///modules/mynginx/50x.html',
    require => File[$error_pages_dir],
    notify  => Service[$service_name],
  }

  if $manage_default_site {
    mynginx::site { 'default': }
  }

  service { $service_name:
    ensure    => running,
    enable    => true,
    require   => Package[$package_name],
    subscribe => [
      File[$config_path],
      File["${error_pages_dir}/40x.html"],
      File["${error_pages_dir}/50x.html"],
    ],
  }
}
