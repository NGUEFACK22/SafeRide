<?php

namespace App\Console\Commands;

use App\Http\Controllers\TripController;
use Illuminate\Console\Command;

class AutoEndInactiveTrips extends Command
{
    protected $signature = 'trips:auto-end-inactive';

    protected $description = 'Clôture automatiquement les trajets EN_COURS inactifs (>10 min) et purge les trajets orphelins en pré-statuts (>15 min)';

    public function handle(): int
    {
        // Réutilise la logique du contrôleur (fin auto 10 min + purge
        // orphelins SCANNE/EN_ATTENTE_TRANSPORTEUR >15 min + notifications).
        $response = app(TripController::class)->autoEndInactive();
        $data = $response->getData(true);

        $closed = $data['closed'] ?? 0;
        if ($closed > 0) {
            $this->info("{$closed} trajet(s) clôturé(s)/annulé(s) automatiquement.");
        } else {
            $this->info('Aucun trajet à clôturer.');
        }

        return Command::SUCCESS;
    }
}
