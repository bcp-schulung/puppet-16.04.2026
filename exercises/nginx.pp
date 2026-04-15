node 'nginx' {
    package { 'nginx':
        ensure => installed,
    }

    service { 'nginx':
        ensure => running,
        enable => true,
        require => Package['nginx'],
    }

    file { '/var/www/html/index.html':
        ensure  => file,
        content => inline_template(file('/etc/puppet/code/environments/production/manifests/index.html')),
        owner   => 'www-data',
        group   => 'www-data',
        mode    => '0644',
        require => Package['nginx'],
        notify  => Service['nginx'],
    }
}