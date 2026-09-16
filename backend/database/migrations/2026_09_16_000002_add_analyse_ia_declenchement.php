<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Nouveau mode de déclenchement SOS : ANALYSE_IA — le SOS parti
 * automatiquement quand l'IA a détecté une anomalie (détour, arrêt, perte
 * GPS) sans réponse des parties. Différenciable de BOUTON (manuel) et VOCAL.
 *
 * SQLite (tests) : l'enum porte un CHECK, régénéré avec le nouveau membre.
 * PostgreSQL (prod) : contrainte CHECK du même nom, drop + recreate.
 */
return new class extends Migration
{
    private const MODES = ['VOCAL', 'BOUTON', 'ANALYSE_IA'];

    public function up(): void
    {
        if (DB::getDriverName() === 'pgsql') {
            DB::statement('ALTER TABLE sos_alerts DROP CONSTRAINT IF EXISTS sos_alerts_declenchement_check');
            DB::statement("ALTER TABLE sos_alerts ADD CONSTRAINT sos_alerts_declenchement_check CHECK (declenchement IN ('" . implode("','", self::MODES) . "'))");
        } else {
            Schema::table('sos_alerts', function (Blueprint $table) {
                $table->enum('declenchement', self::MODES)->change();
            });
        }
    }

    public function down(): void
    {
        if (DB::getDriverName() === 'pgsql') {
            DB::statement('ALTER TABLE sos_alerts DROP CONSTRAINT IF EXISTS sos_alerts_declenchement_check');
            DB::statement("ALTER TABLE sos_alerts ADD CONSTRAINT sos_alerts_declenchement_check CHECK (declenchement IN ('VOCAL','BOUTON'))");
        } else {
            Schema::table('sos_alerts', function (Blueprint $table) {
                $table->enum('declenchement', ['VOCAL', 'BOUTON'])->change();
            });
        }
    }
};
