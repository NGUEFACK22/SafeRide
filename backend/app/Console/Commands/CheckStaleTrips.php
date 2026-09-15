<?php

namespace App\Console\Commands;

use App\Services\AiService;
use Illuminate\Console\Command;

class CheckStaleTrips extends Command
{
    protected $signature = 'trips:check-stale';

    protected $description = 'Watchdog serveur : vérifications MOVEMENT_LOSS pour les trajets EN_COURS sans position GPS depuis > 10 min (téléphone éteint/hors-réseau)';

    public function handle(AiService $ai): int
    {
        $created = $ai->checkStaleTrips();

        if ($created > 0) {
            $this->info("{$created} vérification(s) MOVEMENT_LOSS créée(s) — SOS automatique sous 5 min si aucune réponse.");
        } else {
            $this->info('Aucun trajet actif sans signal GPS.');
        }

        return Command::SUCCESS;
    }
}
