<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Third Party Services
    |--------------------------------------------------------------------------
    |
    | This file is for storing the credentials for third party services such
    | as Mailgun, Postmark, AWS and more. This file provides the de facto
    | location for this type of information, allowing packages to have
    | a conventional file to locate the various service credentials.
    |
    */

    'postmark' => [
        'key' => env('POSTMARK_API_KEY'),
    ],

    'resend' => [
        'key' => env('RESEND_API_KEY'),
    ],

    'ses' => [
        'key' => env('AWS_ACCESS_KEY_ID'),
        'secret' => env('AWS_SECRET_ACCESS_KEY'),
        'region' => env('AWS_DEFAULT_REGION', 'us-east-1'),
    ],

    'slack' => [
        'notifications' => [
            'bot_user_oauth_token' => env('SLACK_BOT_USER_OAUTH_TOKEN'),
            'channel' => env('SLACK_BOT_USER_DEFAULT_CHANNEL'),
        ],
    ],

    'osrm' => [
        'base_url' => env('OSRM_BASE_URL', 'https://router.project-osrm.org'),
    ],

    'ai' => [
        'enabled' => env('AI_ENABLED', false),
        'base_url' => env('AI_BASE_URL', 'https://api.mistral.ai/v1'),
        'api_key' => env('AI_API_KEY'),
        'model' => env('AI_MODEL', 'mistral-small-latest'),
        'timeout' => env('AI_TIMEOUT', 20),
    ],

    'didit' => [
        'key' => env('DIDIT_API_KEY'),
        'base_url' => env('DIDIT_BASE_URL', 'https://verification.didit.me/v3'),
    ],

    'google' => [
        'client_id' => env('GOOGLE_CLIENT_ID'),
        'android_client_id' => env('GOOGLE_ANDROID_CLIENT_ID'),
    ],

    'infobip' => [
        'base_url' => env('INFOBIP_BASE_URL', 'https://api.infobip.com'),
        'api_key' => env('INFOBIP_API_KEY'),
        'sender' => env('INFOBIP_SENDER', 'SafeRide'),
    ],

    'whatsapp' => [
        'sender' => env('INFOBIP_WHATSAPP_SENDER', env('INFOBIP_SENDER', 'SafeRide')),
        // Si INFOBIP_WHATSAPP_SENDER est vide, WhatsappService::ready() = false -> seul SMS
    ],

];
