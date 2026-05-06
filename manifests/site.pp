# Production environment — managed by r10k
node default {
  file { '/tmp/puppet_deployed':
    ensure  => present,
    content => "Puppet is working!\n",
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
  }

  notify { 'puppet_check_in':
    message => "Node ${trusted['certname']} checked in at production.",
  }
}
