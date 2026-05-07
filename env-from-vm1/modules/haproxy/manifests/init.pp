class haproxy (
  Integer $frontend_port = 3000,
  Integer $backend_port   = 3001,
  String  $user         = 'haproxy',
  String  $group        = 'haproxy',
  String  $config_file   = '/etc/haproxy/haproxy.cfg',
) {
  package { 'haproxy':
    ensure => installed,
  }

  service { 'haproxy':
    ensure  => running,
    enable  => true,
    require => Package['haproxy'],
  }

  #file { '/etc/systemd/system/haproxy.service':
  #  ensure  => file,
  #  owner   => 'root',
  #  group   => 'root',
  #  mode    => '0644',
  #  content => epp('haproxy/haproxy.service.epp', {
  #    'user'    => $user,
  #    'group'   => $group,
  #    'config_file' => $config_file,
  #  }),
  #  notify  => Exec['haproxy-reload'],
  #}

  #exec { 'haproxy-reload':
  #  command     => '/bin/systemctl daemon-reload',
  #  refreshonly => true,
  #  notify      => Service['haproxy'],
  #}

  file { '/etc/haproxy/haproxy.cfg':
    ensure  => file,
    content => epp('haproxy/haproxy.cfg.epp', {
      frontend_port => $frontend_port,
      backend_port  => $backend_port,
    }),
    notify  => Service['haproxy'],
  }
}
