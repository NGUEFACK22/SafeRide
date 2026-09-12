<?php

namespace App\Console\Commands;

use App\Http\Controllers\AnomalyVerificationController;
use Illuminate\Console\Command;

class CheckAnomalyTimeouts extends Command
{
    protected $signature = 'anomaly:check-timeouts';

    protected $description = 'Déclenche les SOS automatiques pour les vérifications d\'anomalies en timeout (> 3 min sans réponse)';

    public function handle(): int
    {
        $count = AnomalyVerificationController::processTimeouts();

        if ($count > 0) {
            $this->info("{$count} SOS automatique(s) déclenché(s) pour anomalie(s) en timeout.");
        } else {
            $this->info('Aucun timeout en attente.');
        }

        return Command::SUCCESS;
    }
}
