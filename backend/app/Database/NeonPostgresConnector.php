<?php

namespace App\Database;

use Illuminate\Database\Connectors\PostgresConnector;

/**
 * Connecteur PostgreSQL pour Neon.
 * Laravel n'ajoute pas le paramètre `options=endpoint=...` (requis par le
 * pooler Neon quand libpq ne gère pas le SNI) ni `channel_binding`.
 * On étend le connecteur par défaut pour les transmettre au DSN.
 */
class NeonPostgresConnector extends PostgresConnector
{
    protected function addSslOptions($dsn, array $config)
    {
        foreach (['sslmode', 'sslcert', 'sslkey', 'sslrootcert'] as $option) {
            if (isset($config[$option])) {
                $dsn .= ";{$option}={$config[$option]}";
            }
        }

        if (! empty($config['neon_endpoint'])) {
            $dsn .= ";options=endpoint={$config['neon_endpoint']}";
        }

        return $dsn;
    }
}
