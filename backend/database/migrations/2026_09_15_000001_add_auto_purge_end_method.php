<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        // Étend le CHECK de trips.end_method avec AUTO_PURGE : les orphelins
        // en pré-statuts (SCANNE/CONFIRME/... > 15 min) sont annulés par la
        // purge planifiée, et non par la clôture 10 min des EN_COURS.
        // Séparer les deux motifs rend l'audit lisible.
        if (DB::getDriverName() !== 'pgsql') {
            return;
        }

        DB::statement("ALTER TABLE trips DROP CONSTRAINT IF EXISTS trips_end_method_check");
        DB::statement("ALTER TABLE trips ADD CONSTRAINT trips_end_method_check CHECK (end_method::text = ANY (ARRAY['MANUEL'::character varying, 'AUTO_10MIN'::character varying, 'REFUS_TRANSPORTEUR'::character varying, 'ANNULATION_PASSAGER'::character varying, 'AUTO_PURGE'::character varying]::text[]))");
    }

    public function down(): void
    {
        if (DB::getDriverName() !== 'pgsql') {
            return;
        }

        DB::statement("ALTER TABLE trips DROP CONSTRAINT IF EXISTS trips_end_method_check");
        DB::statement("ALTER TABLE trips ADD CONSTRAINT trips_end_method_check CHECK (end_method::text = ANY (ARRAY['MANUEL'::character varying, 'AUTO_10MIN'::character varying, 'REFUS_TRANSPORTEUR'::character varying, 'ANNULATION_PASSAGER'::character varying]::text[]))");
    }
};
