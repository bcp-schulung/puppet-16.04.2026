#
class profile::postgres (
  Hash $database,
) {
  class { 'postgres':
    pg_database => $database['db_name'],
    pg_user     => $database['db_user'],
    pg_password => $database['db_pass'],
  }
}
