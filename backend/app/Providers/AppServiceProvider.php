<?php

namespace App\Providers;

use App\Models\ManagerAssignment;
use App\Models\SosAlert;
use App\Models\Trip;
use App\Models\User;
use App\Observers\ManagerAssignmentObserver;
use App\Observers\SosAlertObserver;
use App\Observers\TripObserver;
use App\Observers\UserObserver;
use App\Database\NeonPostgresConnector;
use Illuminate\Database\Eloquent\Relations\Relation;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        // Connecteur PostgreSQL compatible Neon (transmet endpoint + channel_binding)
        $this->app->bind('db.connector.pgsql', fn () => new NeonPostgresConnector());
    }

    public function boot(): void
    {
        Relation::morphMap([
            'OBJET_PERDU' => \App\Models\LostItemReport::class,
            'LITIGE' => \App\Models\Dispute::class,
            'SOS' => \App\Models\SosAlert::class,
            'IDENTITE' => \App\Models\IdentityVerification::class,
        ]);

        // Audit logs automatiques (Point 18)
        User::observe(UserObserver::class);
        Trip::observe(TripObserver::class);
        SosAlert::observe(SosAlertObserver::class);
        ManagerAssignment::observe(ManagerAssignmentObserver::class);
    }
}