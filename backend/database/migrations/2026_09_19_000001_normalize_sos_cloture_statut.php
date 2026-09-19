<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Database\Schema\Blueprint;

/**
 * Normalisation SOS : CLOTE (faute de frappe initiale) → CLOTURE.
 * Aligne la contrainte CHECK PostgreSQL, l'enum SQLite et les données
 * existantes sur la valeur canonique CLOTURE utilisée par le code.
 */
return new class extends Migration
{
    public function up(): void
    {
        // 1) Données existantes éventuelles.
        DB::table('sos_alerts')->where('statut', 'CLOTE')->update(['statut' => 'CLOTURE']);

        // 2) Contrainte / enum.
        if (DB::getDriverName() === 'pgsql') {
            DB::statement('ALTER TABLE sos_alerts DROP CONSTRAINT IF EXISTS sos_alerts_statut_check');
            DB::statement("ALTER TABLE sos_alerts ADD CONSTRAINT sos_alerts_statut_check CHECK (statut IN ('DETECTE','VERIFICATION','DECLENCHE','NOTIFIE','EN_COURS','RESOLU','FAUSSE_ALERTE','CLOTURE'))");
        } else {
            Schema::table('sos_alerts', function (Blueprint $table) {
                $table->enum('statut', ['DETECTE', 'VERIFICATION', 'DECLENCHE', 'NOTIFIE', 'EN_COURS', 'RESOLU', 'FAUSSE_ALERTE', 'CLOTURE'])->change();
            });
        }
    }

    public function down(): void
    {
        if (DB::getDriverName() === 'pgsql') {
            DB::statement('ALTER TABLE sos_alerts DROP CONSTRAINT IF EXISTS sos_alerts_statut_check');
            DB::statement("ALTER TABLE sos_alerts ADD CONSTRAINT sos_alerts_statut_check CHECK (statut IN ('DETECTE','VERIFICATION','DECLENCHE','NOTIFIE','EN_COURS','RESOLU','FAUSSE_ALERTE','CLOTE'))");
        } else {
            Schema::table('sos_alerts', function (Blueprint $table) {
                $table->enum('statut', ['DETECTE', 'VERIFICATION', 'DECLENCHE', 'NOTIFIE', 'EN_COURS', 'RESOLU', 'FAUSSE_ALERTE', 'CLOTE'])->change();
            });
        }
    }
};
