<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        // Étend le CHECK de trips.statut avec EN_ATTENTE_TRANSPORTEUR
        // et celui de trips.end_method avec REFUS_TRANSPORTEUR (base existante).
        // SQLite (tests) ne supporte pas ALTER CONSTRAINT : les enums y sont
        // déjà définis dans la migration de création.
        if (DB::getDriverName() !== 'pgsql') {
            return;
        }

        DB::statement("ALTER TABLE trips DROP CONSTRAINT IF EXISTS trips_statut_check");
        DB::statement("ALTER TABLE trips ADD CONSTRAINT trips_statut_check CHECK (statut::text = ANY (ARRAY['SCANNE'::character varying, 'EN_ATTENTE_TRANSPORTEUR'::character varying, 'CONFIRME'::character varying, 'DESTINATION_PROPOSEE'::character varying, 'DESTINATION_CONFIRMEE'::character varying, 'EN_COURS'::character varying, 'TERMINE'::character varying, 'ANNULE'::character varying]::text[]))");

        DB::statement("ALTER TABLE trips DROP CONSTRAINT IF EXISTS trips_end_method_check");
        DB::statement("ALTER TABLE trips ADD CONSTRAINT trips_end_method_check CHECK (end_method::text = ANY (ARRAY['MANUEL'::character varying, 'AUTO_10MIN'::character varying, 'REFUS_TRANSPORTEUR'::character varying]::text[]))");
    }

    public function down(): void
    {
        if (DB::getDriverName() !== 'pgsql') {
            return;
        }

        DB::statement("ALTER TABLE trips DROP CONSTRAINT IF EXISTS trips_statut_check");
        DB::statement("ALTER TABLE trips ADD CONSTRAINT trips_statut_check CHECK (statut::text = ANY (ARRAY['SCANNE'::character varying, 'CONFIRME'::character varying, 'DESTINATION_PROPOSEE'::character varying, 'DESTINATION_CONFIRMEE'::character varying, 'EN_COURS'::character varying, 'TERMINE'::character varying, 'ANNULE'::character varying]::text[]))");

        DB::statement("ALTER TABLE trips DROP CONSTRAINT IF EXISTS trips_end_method_check");
        DB::statement("ALTER TABLE trips ADD CONSTRAINT trips_end_method_check CHECK (end_method::text = ANY (ARRAY['MANUEL'::character varying, 'AUTO_10MIN'::character varying]::text[]))");
    }
};