<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (DB::getDriverName() === 'pgsql') {
            // PostgreSQL : l'enum est un varchar + contrainte check inline.
            // On supprime la contrainte pour autoriser RAPPORT_HEBDOMADAIRE.
            DB::statement('ALTER TABLE ai_reports DROP CONSTRAINT IF EXISTS ai_reports_type_check');
            DB::statement('ALTER TABLE ai_reports ALTER COLUMN type TYPE varchar(255)');
        } else {
            Schema::table('ai_reports', function (Blueprint $table) {
                $table->enum('type', [
                    'RESUME_TRAJET',
                    'STATISTIQUES',
                    'ANOMALIE',
                    'RECOMMANDATION',
                    'RAPPORT_HEBDOMADAIRE',
                ])->change();
            });
        }
    }

    public function down(): void
    {
        if (DB::getDriverName() === 'pgsql') {
            DB::statement('ALTER TABLE ai_reports ALTER COLUMN type TYPE varchar(255)');
        } else {
            Schema::table('ai_reports', function (Blueprint $table) {
                $table->enum('type', [
                    'RESUME_TRAJET',
                    'STATISTIQUES',
                    'ANOMALIE',
                    'RECOMMANDATION',
                ])->change();
            });
        }
    }
};
