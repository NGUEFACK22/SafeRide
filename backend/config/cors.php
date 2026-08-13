<?php

return [
    // Origines autorisées. '*' = toutes (convenable pour une soutenance / démo).
    // En production, restreindre à la liste des origines de l'app.
    'allowed_origins' => explode(',', env('CORS_ALLOWED_ORIGINS', '*')),

    'allowed_methods' => ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],

    'allowed_headers' => ['*'],

    'supports_credentials' => false,

    'max_age' => 0,
];
