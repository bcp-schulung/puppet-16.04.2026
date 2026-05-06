# Dev environment — managed by r10k
node 'vm-2' {
  class { 'frontend':
    port         => 3000,
    backend_host => 'localhost',
  }

  class { 'backend':
    port          => 3001,
    frontend_host => 'localhost',
    db_host       => 'localhost',
    db_user       => 'joker',
    db_database   => 'jokes',
    db_password   => 'letmein',
  }

  class { 'postgres':
    pg_database => 'jokes',
    pg_user     => 'joker',
    pg_password => 'letmein',
  }
}

node default {
  file { '/tmp/puppet_deployed':
    ensure  => present,
    content => "Puppet is working! This is the dev environment.\n",
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
  }

  notify { 'puppet_check_in':
    message => "Node ${trusted['certname']} checked in at dev.",
  }
}
