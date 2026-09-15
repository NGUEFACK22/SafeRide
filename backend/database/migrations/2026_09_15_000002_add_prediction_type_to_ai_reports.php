<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Nouveau type de rapport IA : PREDICTION (climat + heure des bouchons +
 * conseils d'évitement, bouton PRÉDICTION de l'accueil mobile).
 *
 * PostgreSQL (prod) : le type est un varchar sans contrainte depuis la
 * migration 2026_08_18 — rien à faire. SQLite (tests) : l'enum porte un
 * CHECK, on le régénère avec le nouveau membre.
 */
return new class extends Migration
{
    private const TYPES = [
        'RESUME_TRAJET',
        'STATISTIQUES',
        'ANOMALIE',
        'RECOMMANDATION',
        'RAPPORT_HEBDOMADAIRE',
        'PREDICTION',
    ];

    public function up(): void
    {
        if (DB::getDriverName() !== 'pgsql') {
            Schema::table('ai_reports', function (Blueprint $table) {
                $table->enum('type', self::TYPES)->change();
            });
        }
    }

    public function down(): void
    {
        if (DB::getDriverName() !== 'pgsql') {
            Schema::table('ai_reports', function (Blueprint $table) {
                $table->enum('type', array_diff(self::TYPES, ['PREDICTION']))->change();
            });
        }
    }
};
