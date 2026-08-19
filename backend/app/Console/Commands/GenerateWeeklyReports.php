<?php

namespace App\Console\Commands;

use App\Models\User;
use App\Services\AiService;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Log;

/**
 * Génère le résumé IA hebdomadaire (RAPPORT_HEBDOMADAIRE) pour chaque
 * utilisateur actif. Planifiée le dimanche (routes/console.php).
 */
class GenerateWeeklyReports extends Command
{
    protected $signature = 'ai:weekly-reports';

    protected $description = 'Génère le résumé IA hebdomadaire de chaque utilisateur (dimanche)';

    public function handle(AiService $ai): int
    {
        $users = User::where('statut', 'ACTIF')->get();
        $count = 0;

        foreach ($users as $user) {
            try {
                $ai->weeklyReport($user);
                $count++;
            } catch (\Throwable $e) {
                Log::warning('Échec génération rapport hebdomadaire', [
                    'user_id' => $user->id,
                    'error' => $e->getMessage(),
                ]);
            }
        }

        $this->info("Rapports hebdomadaires générés pour {$count} utilisateur(s).");

        return self::SUCCESS;
    }
}
