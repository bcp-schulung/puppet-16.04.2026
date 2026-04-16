define mynginx::site (
  String           $docroot       = '/var/www/mynginx',
  String           $server_name   = '_',
  Integer          $listen_port   = 80,
  Boolean          $default_site  = true,
  Boolean          $manage_index  = true,
  Optional[String] $index_content = undef,
) {
  $listen_suffix = $default_site ? {
    true    => ' default_server',
    default => '',
  }

  $page_content = $index_content ? {
    undef   => @("HTML"/L)
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="utf-8">
        <title>${title}</title>
      </head>
      <body>
        <h1>${title}</h1>
        <p>This page is managed by the mynginx Puppet module.</p>
        <p>Document root: ${docroot}</p>
      </body>
      </html>
      | HTML,
    default => $index_content,
  }

  file { $docroot:
    ensure  => directory,
    owner   => 'www-data',
    group   => 'www-data',
    mode    => '0755',
    require => Class['mynginx'],
  }

  if $manage_index {
    file { "${docroot}/index.html":
      ensure  => file,
      owner   => 'www-data',
      group   => 'www-data',
      mode    => '0644',
      content => $page_content,
      require => File[$docroot],
    }
  }

  file { "/etc/nginx/sites-available/${title}":
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => epp('mynginx/site.conf.epp', {
      'docroot'       => $docroot,
      'server_name'   => $server_name,
      'listen_port'   => $listen_port,
      'listen_suffix' => $listen_suffix,
    }),
    require => Class['mynginx'],
    notify  => Service['nginx'],
  }

  file { "/etc/nginx/sites-enabled/${title}":
    ensure  => link,
    target  => "/etc/nginx/sites-available/${title}",
    require => File["/etc/nginx/sites-available/${title}"],
    notify  => Service['nginx'],
  }
}
