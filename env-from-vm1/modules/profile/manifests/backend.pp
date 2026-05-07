#
class profile::backend (
  Hash $database,
) {
  class { 'backend':
    db_database => $database['db_name'],
    db_user     => $database['db_user'],
    db_password => $database['db_pass'],
  }
}
