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
