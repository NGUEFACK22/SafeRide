<?php

namespace App\Observers;

use App\Models\AuditLog;
use App\Models\ManagerAssignment;
use Illuminate\Support\Facades\Request;

class ManagerAssignmentObserver
{
    public function created(ManagerAssignment $assignment): void
    {
        AuditLog::create([
            'user_id' => $assignment->manager_id,
            'action' => 'assignment_created',
            'entity_type' => 'ManagerAssignment',
            'entity_id' => $assignment->id,
            'details' => [
                'dossier_type' => $assignment->dossier_type,
                'dossier_id' => $assignment->dossier_id,
                'statut' => $assignment->statut,
            ],
            'ip' => Request::ip(),
            'user_agent' => Request::userAgent(),
        ]);
    }

    public function updated(ManagerAssignment $assignment): void
    {
        if ($assignment->wasChanged('taken_at') && $assignment->taken_at) {
            $this->log($assignment, 'assignment_taken');
        }

        if ($assignment->wasChanged('closed_at') && $assignment->closed_at) {
            $this->log($assignment, 'assignment_closed');
        }
    }

    protected function log(ManagerAssignment $assignment, string $action): void
    {
        AuditLog::create([
            'user_id' => $assignment->manager_id,
            'action' => $action,
            'entity_type' => 'ManagerAssignment',
            'entity_id' => $assignment->id,
            'details' => [
                'dossier_type' => $assignment->dossier_type,
                'dossier_id' => $assignment->dossier_id,
            ],
            'ip' => Request::ip(),
            'user_agent' => Request::userAgent(),
        ]);
    }
}
