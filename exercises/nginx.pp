node 'nginx' {
  class { 'mynginx':
    manage_default_site => false,
  }

  mynginx::site { 'default':
    docroot      => '/srv/my-node-content',
    manage_index => true,
  }
}