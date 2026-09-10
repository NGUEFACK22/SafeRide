<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        // Étend le CHECK de trips.end_method avec ANNULATION_PASSAGER
        // (annulation de la demande de course par le passager avant départ).
        // SQLite (tests) ne supporte pas ALTER CONSTRAINT : les enums y sont
        // déjà définis dans la migration de création.
        if (DB::getDriverName() !== 'pgsql') {
            return;
        }

        DB::statement("ALTER TABLE trips DROP CONSTRAINT IF EXISTS trips_end_method_check");
        DB::statement("ALTER TABLE trips ADD CONSTRAINT trips_end_method_check CHECK (end_method::text = ANY (ARRAY['MANUEL'::character varying, 'AUTO_10MIN'::character varying, 'REFUS_TRANSPORTEUR'::character varying, 'ANNULATION_PASSAGER'::character varying]::text[]))");
    }

    public function down(): void
    {
        if (DB::getDriverName() !== 'pgsql') {
            return;
        }

        DB::statement("ALTER TABLE trips DROP CONSTRAINT IF EXISTS trips_end_method_check");
        DB::statement("ALTER TABLE trips ADD CONSTRAINT trips_end_method_check CHECK (end_method::text = ANY (ARRAY['MANUEL'::character varying, 'AUTO_10MIN'::character varying, 'REFUS_TRANSPORTEUR'::character varying]::text[]))");
    }
};
