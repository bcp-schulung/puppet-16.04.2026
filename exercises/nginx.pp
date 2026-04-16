node 'nginx-1' {
  require ufw

  class { 'mynginx':
    manage_default_site => false,
  }

  mynginx::site { 'default':
    docroot      => '/srv/my-node-content',
    manage_index => true,
  }

  ufw_rule { 'allow ssh':
    action       => 'allow',
    to_ports_app => 22,
  }

  ufw_rule { 'allow http on eth0':
    action       => 'allow',
    to_ports_app => 80,
    interface    => 'eth0',
  }

  ufw_rule { 'allow https on eth0':
    action       => 'allow',
    to_ports_app => 443,
    interface    => 'eth0',
  }
}