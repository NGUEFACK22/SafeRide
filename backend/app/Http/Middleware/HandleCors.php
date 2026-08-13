<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Middleware CORS minimal (sans dépendance externe) permettant à l'API
 * d'être appelée depuis n'importe quelle origine (émulateur, appareil physique,
 * navigateur web, Postman…). Point critique pour le fonctionnement « partout ».
 */
class HandleCors
{
    public function handle(Request $request, Closure $next): Response
    {
        $origins = config('cors.allowed_origins', ['*']);
        $allowedOrigin = $this->resolveOrigin($request, $origins);

        $headers = [
            'Access-Control-Allow-Origin' => $allowedOrigin,
            'Access-Control-Allow-Methods' => implode(', ', config('cors.allowed_methods', ['*'])),
            'Access-Control-Allow-Headers' => implode(', ', config('cors.allowed_headers', ['*'])),
            'Access-Control-Max-Age' => (string) config('cors.max_age', 0),
        ];

        if (config('cors.supports_credentials', false)) {
            $headers['Access-Control-Allow-Credentials'] = 'true';
        }

        // Réponse directe pour les requêtes preflight OPTIONS
        if ($request->getMethod() === 'OPTIONS'
            && ($request->header('Access-Control-Request-Method')
                || $request->header('Access-Control-Request-Headers'))) {
            return response('', 204)->withHeaders($headers);
        }

        $response = $next($request);

        foreach ($headers as $key => $value) {
            $response->headers->set($key, $value);
        }

        return $response;
    }

    protected function resolveOrigin(Request $request, array $origins): string
    {
        $requestOrigin = $request->header('Origin');

        if (in_array('*', $origins, true)) {
            return '*';
        }

        if ($requestOrigin !== null && in_array($requestOrigin, $origins, true)) {
            return $requestOrigin;
        }

        return $origins[0] ?? '*';
    }
}
