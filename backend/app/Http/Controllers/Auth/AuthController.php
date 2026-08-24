<?php

namespace App\Http\Controllers\Auth;

use App\Http\Controllers\Controller;
use App\Models\AuditLog;
use App\Models\User;
use App\Services\GoogleAuthService;
use App\Mail\VerificationMail;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Mail;
use Illuminate\Support\Facades\Password;
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
            'role' => 'nullable|in:passager,transporteur',
        ]);

        $role = $data['role'] ?? 'passager';

        $user = User::create([
            'nom' => $data['nom'],
            'prenom' => $data['prenom'],
            'email' => $data['email'],
            'telephone' => $data['telephone'],
            'password' => Hash::make($data['password']),
            'statut' => 'ACTIF',
        ]);

        $user->assignRole($role);

        // I.31b : envoi email de vérification (non bloquant)
        try {
            Mail::to($user->email)->send(new VerificationMail($user));
        } catch (\Throwable $e) {
            \Log::warning('Verification email failed', ['email' => $user->email, 'error' => $e->getMessage()]);
        }

        $token = $user->createToken('auth')->plainTextToken;

        return response()->json([
            'message' => 'Inscription réussie — vérifiez votre email',
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

        // P1-5 : validation stricte des claims requis
        if (empty($claims['email']) || empty($claims['sub'])) {
            return response()->json(['message' => 'Jeton Google incomplet (email/sub manquant)'], 401);
        }
        if (isset($claims['email_verified']) && $claims['email_verified'] !== true && $claims['email_verified'] !== 'true' && $claims['email_verified'] !== 1 && $claims['email_verified'] !== '1') {
            return response()->json(['message' => 'Email Google non vérifié'], 401);
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

    public function deleteAccount(Request $request): JsonResponse
    {
        $user = $request->user();
        $user->tokens()->delete();
        $user->delete();

        return response()->json(['message' => 'Compte supprimé avec succès']);
    }

    public function sendVerification(Request $request): JsonResponse
    {
        $user = $request->user();
        if ($user->hasVerifiedEmail()) {
            return response()->json(['message' => 'Email déjà vérifié']);
        }
        $user->sendEmailVerificationNotification();
        // Fallback si notification non configurée : envoi direct
        try {
            \Mail::to($user->email)->send(new \App\Mail\VerificationMail($user));
        } catch (\Throwable $e) {}
        return response()->json(['message' => 'Email de vérification envoyé']);
    }

    public function verifyEmail(Request $request, int $id, string $hash): JsonResponse
    {
        $user = User::findOrFail($id);
        if (! hash_equals(sha1($user->email), $hash)) {
            return response()->json(['message' => 'Lien invalide'], 400);
        }
        if (!$request->hasValidSignature()) {
            return response()->json(['message' => 'Lien expiré'], 400);
        }
        $user->markEmailAsVerified();
        return response()->json(['message' => 'Email vérifié avec succès']);
    }

    public function forgotPassword(Request $request): JsonResponse
    {
        $data = $request->validate(['email' => 'required|email']);
        $status = Password::sendResetLink($data);
        return $status === Password::RESET_LINK_SENT
            ? response()->json(['message' => 'Lien de réinitialisation envoyé par email'])
            : response()->json(['message' => 'Email non trouvé'], 404);
    }

    public function resetPassword(Request $request): JsonResponse
    {
        $data = $request->validate([
            'email' => 'required|email',
            'token' => 'required|string',
            'password' => 'required|string|min:8|confirmed',
        ]);
        $status = Password::reset($data, function ($user, $password) {
            $user->forceFill(['password' => Hash::make($password)])->save();
        });
        return $status === Password::PASSWORD_RESET
            ? response()->json(['message' => 'Mot de passe réinitialisé avec succès'])
            : response()->json(['message' => 'Token invalide ou expiré'], 422);
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