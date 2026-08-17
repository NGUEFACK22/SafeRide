<?php

namespace App\Http\Controllers\Auth;

use App\Http\Controllers\Controller;
use App\Models\AuditLog;
use App\Models\User;
use App\Services\GoogleAuthService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;

class AuthController extends Controller
{
    public function register(Request $request): JsonResponse
    {
        $data = $request->validate([
            'nom' => 'required|string|max:100',
            'prenom' => 'required|string|max:100',
            'email' => 'required|email|unique:users,email',
            'telephone' => 'required|string|max:20|unique:users,telephone',
            'password' => 'required|string|min:8',
        ]);

        $user = User::create([
            'nom' => $data['nom'],
            'prenom' => $data['prenom'],
            'email' => $data['email'],
            'telephone' => $data['telephone'],
            'password' => Hash::make($data['password']),
            'statut' => 'ACTIF',
        ]);

        $user->assignRole('passager');

        $token = $user->createToken('auth')->plainTextToken;

        return response()->json([
            'message' => 'Inscription réussie',
            'token' => $token,
            'user' => $this->userPayload($user),
        ], 201);
    }

    public function login(Request $request): JsonResponse
    {
        $data = $request->validate([
            'email' => 'required|email',
            'password' => 'required|string',
        ]);

        $user = User::with('roles')->where('email', $data['email'])->first();

        if (! $user || ! Hash::check($data['password'], $user->password)) {
            return response()->json(['message' => 'Identifiants invalides'], 401);
        }

        if ($user->statut === 'SUSPENDU') {
            return response()->json(['message' => 'Compte suspendu. Contactez l\'administration.'], 403);
        }

        $token = $user->createToken('auth')->plainTextToken;

        AuditLog::create([
            'user_id' => $user->id,
            'action' => 'login',
            'entity_type' => 'User',
            'entity_id' => $user->id,
            'details' => ['email' => $user->email],
            'ip' => $request->ip(),
            'user_agent' => $request->userAgent(),
        ]);

        return response()->json([
            'message' => 'Connexion réussie',
            'token' => $token,
            'user' => $this->userPayload($user),
        ]);
    }

    /**
     * Connexion / inscription via compte Google (OAuth).
     * Le mobile envoie l'ID token reçu de Google ; il est vérifié côté serveur
     * et un compte est créé automatiquement si l'email est inconnu.
     */
    public function google(Request $request): JsonResponse
    {
        $data = $request->validate([
            'id_token' => 'required|string',
            'telephone' => 'nullable|string|max:20',
        ]);

        $claims = app(GoogleAuthService::class)->verifyIdToken($data['id_token']);

        if ($claims === null) {
            return response()->json(['message' => 'Jeton Google invalide'], 401);
        }

        $email = strtolower($claims['email']);
        $user = User::where('email', $email)->first();

        if ($user === null) {
            $user = User::create([
                'nom' => $claims['family_name'] ?? ($claims['name'] ?? 'Google'),
                'prenom' => $claims['given_name'] ?? $claims['name'] ?? 'Utilisateur',
                'email' => $email,
                'telephone' => $data['telephone'] ?? null,
                'password' => Hash::make(Str::random(40)),
                'photo_url' => $claims['picture'] ?? null,
                'google_id' => $claims['sub'],
                'email_verified_at' => now(),
                'statut' => 'ACTIF',
            ]);
            $user->assignRole('passager');
        } else {
            if ($user->statut === 'SUSPENDU') {
                return response()->json(['message' => 'Compte suspendu. Contactez l\'administration.'], 403);
            }

            $user->update([
                'google_id' => $user->google_id ?? $claims['sub'],
                'photo_url' => $claims['picture'] ?? $user->photo_url,
            ]);
        }

        $token = $user->createToken('auth')->plainTextToken;

        AuditLog::create([
            'user_id' => $user->id,
            'action' => 'login_google',
            'entity_type' => 'User',
            'entity_id' => $user->id,
            'details' => ['email' => $email],
            'ip' => $request->ip(),
            'user_agent' => $request->userAgent(),
        ]);

        return response()->json([
            'message' => 'Connexion Google réussie',
            'token' => $token,
            'user' => $this->userPayload($user->load('roles')),
        ]);
    }

    public function logout(Request $request): JsonResponse
    {
        $request->user()->currentAccessToken()->delete();

        return response()->json(['message' => 'Déconnexion réussie']);
    }

    public function profile(Request $request): JsonResponse
    {
        $user = $request->user()->load('roles', 'vehicles');

        return response()->json(['user' => $this->userPayload($user)]);
    }

    protected function userPayload(User $user): array
    {
        return [
            'id' => $user->id,
            'nom' => $user->nom,
            'prenom' => $user->prenom,
            'email' => $user->email,
            'telephone' => $user->telephone,
            'photo_url' => $user->photo_url,
            'statut' => $user->statut,
            'roles' => $user->roles->pluck('slug'),
            'created_at' => $user->created_at,
        ];
    }
}