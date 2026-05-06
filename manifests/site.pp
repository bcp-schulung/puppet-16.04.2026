# Puppet training lab — smoke test
node 'vm-4' {
  # haproxy
  class { 'haproxy':
    frontend_port => 3000,
    backend_port  => 3001,
  }
}

node 'vm-5','vm-6','vm-7' {
  # frontend
  class { 'frontend':
    port         => 3000,
    backend_host => $backend_host,
  }
}

node 'vm-8','vm-9', {
  # backend
    class { 'backend':
    port          => 3001,
    frontend_host => $frontend_host,
    db_host       => $db_host,
    db_user       => 'joker',
    db_database   => 'jokes',
    db_password   => 'letmein',
  }
}

node 'vm-10' {
  # db
  class { 'postgres':
    pg_database => 'jokes',
    pg_user     => 'joker',
    pg_password => 'letmein',
  }
}

node default {
  file { '/tmp/puppet_deployed':
    ensure  => present,
    content => "Puppet is working. This is a 'default' node in prod.\n",
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
  }

  notify { 'puppet_check_in':
    message => "Node ${trusted['certname']} checked in successfully.",
  }
}
