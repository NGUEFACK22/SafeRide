<?php

namespace App\Http\Middleware;

use Illuminate\Auth\Middleware\Authenticate as BaseAuthenticate;
use Illuminate\Http\Request;

class Authenticate extends BaseAuthenticate
{
    /**
     * Pas de redirection pour une API : on renvoie null pour que
     * l'exception d'authentification produise une réponse 401 JSON
     * (et non une tentative de redirection vers une route 'login' inexistante).
     */
    protected function redirectTo(Request $request): ?string
    {
        return null;
    }
}
