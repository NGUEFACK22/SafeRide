<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class RoleMiddleware
{
    public function handle(Request $request, Closure $next, string ...$roles): Response
    {
        $user = $request->user();

        if (! $user) {
            return response()->json(['message' => 'Non authentifié'], 401);
        }

        $userRoles = $user->roles()->pluck('slug')->all();

        if (! array_intersect($roles, $userRoles)) {
            return response()->json(['message' => 'Accès refusé. Rôle requis : ' . implode(', ', $roles)], 403);
        }

        return $next($request);
    }
}