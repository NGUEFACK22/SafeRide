<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // Fin de trajet à double confirmation : le 1er qui clique fait passer
        // EN_COURS → FIN_EN_ATTENTE (fin_demandee_par/at), le trajet n'est
        // TERMINE que quand l'autre partie confirme. Sans co-confirmation
        // sous 24h, clôture automatique (AUTO_24H).
        Schema::table('trips', function (Blueprint $table) {
            $table->string('fin_demandee_par', 20)->nullable();
            $table->timestamp('fin_demandee_at')->nullable();
        });

        // SQLite (tests) ne supporte pas ALTER CONSTRAINT : les enums y sont
        // déjà définis dans la migration de création.
        if (DB::getDriverName() !== 'pgsql') {
            return;
        }

        DB::statement("ALTER TABLE trips DROP CONSTRAINT IF EXISTS trips_statut_check");
        DB::statement("ALTER TABLE trips ADD CONSTRAINT trips_statut_check CHECK (statut::text = ANY (ARRAY['SCANNE'::character varying, 'EN_ATTENTE_TRANSPORTEUR'::character varying, 'CONFIRME'::character varying, 'DESTINATION_PROPOSEE'::character varying, 'DESTINATION_CONFIRMEE'::character varying, 'EN_COURS'::character varying, 'FIN_EN_ATTENTE'::character varying, 'TERMINE'::character varying, 'ANNULE'::character varying]::text[]))");

        DB::statement("ALTER TABLE trips DROP CONSTRAINT IF EXISTS trips_end_method_check");
        DB::statement("ALTER TABLE trips ADD CONSTRAINT trips_end_method_check CHECK (end_method::text = ANY (ARRAY['MANUEL'::character varying, 'AUTO_10MIN'::character varying, 'REFUS_TRANSPORTEUR'::character varying, 'ANNULATION_PASSAGER'::character varying, 'AUTO_PURGE'::character varying, 'AUTO_24H'::character varying]::text[]))");
    }

    public function down(): void
    {
        Schema::table('trips', function (Blueprint $table) {
            $table->dropColumn(['fin_demandee_par', 'fin_demandee_at']);
        });

        if (DB::getDriverName() !== 'pgsql') {
            return;
        }

        DB::statement("ALTER TABLE trips DROP CONSTRAINT IF EXISTS trips_statut_check");
        DB::statement("ALTER TABLE trips ADD CONSTRAINT trips_statut_check CHECK (statut::text = ANY (ARRAY['SCANNE'::character varying, 'EN_ATTENTE_TRANSPORTEUR'::character varying, 'CONFIRME'::character varying, 'DESTINATION_PROPOSEE'::character varying, 'DESTINATION_CONFIRMEE'::character varying, 'EN_COURS'::character varying, 'TERMINE'::character varying, 'ANNULE'::character varying]::text[]))");

        DB::statement("ALTER TABLE trips DROP CONSTRAINT IF EXISTS trips_end_method_check");
        DB::statement("ALTER TABLE trips ADD CONSTRAINT trips_end_method_check CHECK (end_method::text = ANY (ARRAY['MANUEL'::character varying, 'AUTO_10MIN'::character varying, 'REFUS_TRANSPORTEUR'::character varying, 'ANNULATION_PASSAGER'::character varying, 'AUTO_PURGE'::character varying]::text[]))");
    }
};
