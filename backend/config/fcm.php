<?php

return [
    // Chemin vers le fichier de compte de service Firebase (ne pas committer)
    'credentials_path' => env('FCM_CREDENTIALS_PATH', base_path('firebase-service-account.json')),
];