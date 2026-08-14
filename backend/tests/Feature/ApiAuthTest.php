<?php

namespace Tests\Feature;

use Tests\TestCase;

class ApiAuthTest extends TestCase
{
    /**
     * Une requête non authentifiée sur une route protégée doit renvoyer 401 JSON,
     * jamais une redirection 500 (route('login') inexistante).
     */
    public function test_unauthenticated_request_returns_401_json(): void
    {
        $response = $this->postJson('/api/v1/identity/submit', [
            'type' => 'CNI',
        ]);

        $response->assertStatus(401)
            ->assertJson(['message' => 'Unauthenticated.']);
    }

    /**
     * Plusieurs routes protégées doivent renvoyer 401 sans token.
     */
    public function test_protected_routes_require_authentication(): void
    {
        $routes = [
            ['GET', '/api/v1/auth/profile'],
            ['GET', '/api/v1/trips/history'],
            ['GET', '/api/v1/ai/summary'],
            ['GET', '/api/v1/identity/status'],
        ];

        foreach ($routes as [$method, $uri]) {
            $this->call($method, $uri)->assertStatus(401);
        }
    }
}
