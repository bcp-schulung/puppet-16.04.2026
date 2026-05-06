# Staging environment — managed by r10k
# Mirrors dev but isolated for pre-production testing.
node default {
  file { '/tmp/puppet_deployed':
    ensure  => present,
    content => "Puppet is working! This is the staging environment.\n",
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
  }

  notify { 'puppet_check_in':
    message => "Node ${trusted['certname']} checked in at staging.",
  }

  class { 'postgres':
    pg_database => 'jokes',
    pg_user     => 'joker',
    pg_password => 'letmein',
  }
}
