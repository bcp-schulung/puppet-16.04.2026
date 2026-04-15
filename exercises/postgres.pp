node 'postgres' {
    package { 'postgresql':
        ensure => installed,
    }

    service { 'postgresql':
        ensure => running,
        enable => true,
        require => Package['postgresql'],
    }
}