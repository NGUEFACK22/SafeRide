<?php

namespace App\Http\Controllers;

use App\Models\Dispute;
use App\Models\IdentityVerification;
use App\Models\LostItemReport;
use App\Models\ManagerAssignment;
use App\Models\SosAlert;
use App\Models\Trip;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;

class AdminController extends Controller
{
    public function dashboard(): JsonResponse
    {
        return response()->json([
            'users_total' => User::count(),
            'trips_total' => Trip::count(),
            'trips_active' => Trip::where('statut', 'EN_COURS')->count(),
            'sos_total' => SosAlert::count(),
            'sos_open' => SosAlert::whereNotIn('statut', ['RESOLU', 'CLOTE', 'FAUSSE_ALERTE'])->count(),
            'disputes_total' => Dispute::count(),
            'lost_items_total' => LostItemReport::count(),
            'identities' => IdentityVerification::count(),
            'managers_total' => ManagerAssignment::select('manager_id')->distinct()->count(),
        ]);
    }

    public function createUser(Request $request): JsonResponse
    {
        $data = $request->validate([
            'nom' => 'required|string|max:100',
            'prenom' => 'required|string|max:100',
            'email' => 'required|email|unique:users,email',
            'telephone' => 'required|string|max:20|unique:users,telephone',
            'password' => 'required|string|min:8',
            'role' => 'required|in:passager,transporteur,gestionnaire,admin',
        ]);

        $user = User::create([
            'nom' => $data['nom'],
            'prenom' => $data['prenom'],
            'email' => $data['email'],
            'telephone' => $data['telephone'],
            'password' => Hash::make($data['password']),
            'statut' => 'ACTIF',
        ]);

        $user->assignRole($data['role']);

        return response()->json([
            'message' => 'Utilisateur ' . $data['role'] . ' créé par l\'administrateur',
            'user' => $user->load('roles'),
        ], 201);
    }

    public function listUsers(Request $request): JsonResponse
    {
        $users = User::with('roles')
            ->when($request->query('role'), fn ($q, $role) => $q->whereHas('roles', fn ($r) => $r->where('slug', $role)))
            ->paginate(20);

        return response()->json(['users' => $users]);
    }

    public function toggleSuspension(Request $request, int $id): JsonResponse
    {
        $user = User::findOrFail($id);

        $user->update([
            'statut' => $user->statut === 'SUSPENDU' ? 'ACTIF' : 'SUSPENDU',
        ]);

        return response()->json([
            'message' => 'Compte ' . ($user->statut === 'SUSPENDU' ? 'suspendu' : 'réactivé'),
            'user' => $user,
        ]);
    }

    public function managerStats(): JsonResponse
    {
        $managers = User::whereHas('roles', fn ($q) => $q->where('slug', 'gestionnaire'))
            ->withCount(['managerAssignments as total' ])
            ->withCount(['managerAssignments as total_resolus' => fn ($q) => $q->where('statut', 'CLOTURE')])
            ->get()
            ->map(function ($manager) {
                $assignments = ManagerAssignment::where('manager_id', $manager->id)->get();
                $closed = $assignments->where('statut', 'CLOTURE');
                $closedAt = $closed->pluck('closed_at');
                $assignedAt = $assignments->pluck('assigned_at');

                return [
                    'id' => $manager->id,
                    'nom' => $manager->nom,
                    'prenom' => $manager->prenom,
                    'total' => $assignments->count(),
                    'résolus' => $closed->count(),
                    'taux_resolution' => $assignments->count() > 0
                        ? round(($closed->count() / $assignments->count()) * 100, 1)
                        : 0,
                    'decompose' => $assignments->groupBy('dossier_type')->map->count(),
                ];
            });

        return response()->json(['managers' => $managers]);
    }

    public function statsByManager(int $id): JsonResponse
    {
        $assignments = ManagerAssignment::with('dossier')
            ->where('manager_id', $id)
            ->latest()
            ->get();

        return response()->json([
            'manager' => User::with('roles')->findOrFail($id),
            'assignments' => $assignments,
            'total' => $assignments->count(),
            'par_statut' => $assignments->groupBy('statut')->map->count(),
        ]);
    }
}