# Database class.
#
# Installs and configures a postgres database
# with the puppetlabs-postgresql module
#
# @param pg_database   Name of the database.
# @param pg_user       Name for the database user.
# @param pg_password   Password for the database user.
# @param pg_version    PostgreSQL major version to install (default: 16).
# @param pg_allowed_ips  Array of CIDRs allowed to connect remotely.
#
class postgres (
    String        $pg_password,
    String        $pg_database    = 'jokes',
    String        $pg_user        = 'joker',
    String        $pg_version     = '16',
    Array[String] $pg_allowed_ips = [],
) {
    class { 'postgresql::globals':
        version => $pg_version,
    }

    class { 'postgresql::server':
        listen_addresses => '*',
    }

    postgresql::server::db { $pg_database:
        user     => $pg_user,
        password => postgresql::postgresql_password($pg_user, $pg_password),
    }

    # PostgreSQL 15+ revoked default CREATE on public schema from PUBLIC.
    # Grant it explicitly so the application user can create tables.
    #postgresql_psql { "grant schema public to ${pg_user} in ${pg_database}":
    #    command => "GRANT CREATE, USAGE ON SCHEMA public TO \"${pg_user}\"",
    #    db      => $pg_database,
    #    unless  => "SELECT 1 FROM information_schema.role_schema_grants " +
    #               "WHERE grantee = '${pg_user}' AND schema_name = 'public' " +
    #               "AND privilege_type = 'CREATE'",
    #    require => Postgresql::Server::Db[$pg_database],
    #}

    ['CREATE', 'USAGE'].each |String $priv| {
        postgresql::server::grant { "Grant ${priv} in public schema to ${pg_user} in ${pg_database}":
            privilege   => $priv,
            object_type => 'SCHEMA',
            object_name => 'public',
            db          => $pg_database,
            role        => $pg_user,
            require     => Postgresql::Server::Db[$pg_database],
        }
    }

    postgresql::server::pg_hba_rule { 'Allow localhost access to database':
        description => "Allow ${pg_user} to access ${pg_database} from localhost",
        type        => 'host',
        database    => $pg_database,
        user        => $pg_user,
        address     => '127.0.0.1/32',
        auth_method => 'md5',
    }

    if ! $pg_allowed_ips.empty {
        $pg_allowed_ips.each |String $cidr| {
            postgresql::server::pg_hba_rule { "Allow network access from ${cidr} to database":
                description => "Allow ${pg_user} to access ${pg_database} from ${cidr}",
                type        => 'host',
                database    => $pg_database,
                user        => $pg_user,
                address     => $cidr,
                auth_method => 'md5',
            }
        }
    }
}
