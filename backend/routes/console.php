<?php

use Illuminate\Foundation\Inspiring;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Schedule;

Artisan::command('inspire', function () {
    $this->comment(Inspiring::quote());
})->purpose('Display an inspiring quote');

// Résumé IA hebdomadaire : chaque dimanche à 08h00.
// (php artisan schedule:run doit être appelé par le cron du serveur)
Schedule::command('ai:weekly-reports')->weeklyOn(0, '08:00');

// Vérification des timeouts d'anomalies : chaque minute.
Schedule::command('anomaly:check-timeouts')->everyMinute();

// Clôture auto des trajets inactifs (>10 min) + purge des trajets orphelins
// en pré-statuts (>15 min) : sans ceci, un passager ayant scanné sans suite
// reste bloqué indéfiniment (le guard start exige un statut clôturé).
Schedule::command('trips:auto-end-inactive')->everyFiveMinutes();
