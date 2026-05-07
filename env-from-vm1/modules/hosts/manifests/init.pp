class hosts {

  file { '/etc/hosts':
    ensure => file,
    owner  => 'root',
    group  => 'root',
    source => 'puppet:///modules/hosts/hosts',
  }

}
