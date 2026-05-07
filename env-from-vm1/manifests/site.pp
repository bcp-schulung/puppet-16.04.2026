# Puppet training lab — smoke test
node 'vm-4' {
  class { 'haproxy':
    frontend_port => 3000,
    backend_port  => 3001,
    user          => 'haproxy',
    group         => 'haproxy',
    config_file   => '/etc/haproxy/haproxy.cfg',
}

  include hosts
}
node 'vm-5','vm-6','vm-7' {
  # frontend
  include hosts
  class { 'frontend': }
}

node 'vm-8','vm-9' {
  # backend
  include role::jokes::backend
  include hosts

}

node 'vm-10' {
  # db
  #class { 'postgres':
  #  pg_database => lookup('jokes::database::db_name'),
  #  pg_user     => lookup('jokes::database::db_user'),
  #  pg_password => lookup('jokes::database::db_pass'),
  #}
  include hosts
  include role::jokes::postgres

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
