<?php

namespace Database\Seeders;

use App\Models\Permission;
use App\Models\Role;
use Illuminate\Database\Seeder;

class RolesAndPermissionsSeeder extends Seeder
{
    public function run(): void
    {
        $permissions = [
            'users' => ['view', 'create', 'update', 'delete'],
            'vehicles' => ['view', 'create', 'update', 'delete'],
            'trips' => ['view', 'create', 'update', 'end'],
            'sos' => ['view', 'create', 'update', 'resolve'],
            'incidents' => ['view', 'create', 'update', 'resolve'],
            'assignments' => ['view', 'create', 'take', 'close'],
            'stats' => ['view_personal', 'view_global'],
            'identity' => ['verify', 'reject', 'review'],
        ];

        $permissionModels = [];
        foreach ($permissions as $resource => $actions) {
            foreach ($actions as $action) {
                $slug = $resource . '.' . $action;
                $permissionModels[$slug] = Permission::firstOrCreate([
                    'slug' => $slug,
                ], [
                    'nom' => ucfirst($resource . ' ' . $action),
                ]);
            }
        }

        $roles = [
            'passager' => 'Passager',
            'transporteur' => 'Transporteur',
            'gestionnaire' => 'Gestionnaire',
            'admin' => 'Administrateur',
        ];

        foreach ($roles as $slug => $nom) {
            Role::firstOrCreate(['slug' => $slug], ['nom' => $nom]);
        }

        $admin = Role::where('slug', 'admin')->first();
        $gestionnaire = Role::where('slug', 'gestionnaire')->first();
        $transporteur = Role::where('slug', 'transporteur')->first();
        $passager = Role::where('slug', 'passager')->first();

        $idOf = fn (string $slug) => $permissionModels[$slug]->id;

        $admin->permissions()->sync(array_map($idOf, array_keys($permissionModels)));

        $gestionnaire->permissions()->sync(array_map($idOf, [
            'trips.view',
            'trips.update',
            'sos.view',
            'sos.update',
            'sos.resolve',
            'incidents.view',
            'incidents.update',
            'incidents.resolve',
            'assignments.view',
            'assignments.take',
            'assignments.close',
            'stats.view_personal',
            'identity.verify',
            'identity.reject',
            'identity.review',
            'users.view',
        ]));

        $transporteur->permissions()->sync(array_map($idOf, [
            'vehicles.view',
            'vehicles.create',
            'vehicles.update',
            'vehicles.delete',
            'trips.view',
            'sos.view',
            'incidents.view',
        ]));

        $passager->permissions()->sync(array_map($idOf, [
            'trips.view',
            'trips.create',
            'trips.end',
            'sos.create',
            'incidents.create',
            'stats.view_personal',
            'users.view',
        ]));
    }
}