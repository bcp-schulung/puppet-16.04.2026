# Dev environment — managed by r10k
# Class parameters are supplied by Hiera (data/common.yaml, data/nodes/<certname>.yaml).
node 'vm-2' {
  include frontend
  include backend
  include postgres
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
