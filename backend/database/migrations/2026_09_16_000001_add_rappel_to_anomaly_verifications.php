<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Escalade bien-être en deux temps (DETOUR / STOP) : si le passager ne
 * répond pas à la 1re fenêtre après 10 min ET que la situation dure encore,
 * une 2e notification (rappel) est envoyée — « rappel_at » marque cet
 * instant. Sans réponse 10 min plus tard, le SOS automatique part.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('anomaly_verifications', function (Blueprint $table) {
            $table->timestamp('rappel_at')->nullable()->after('responded_at');
        });
    }

    public function down(): void
    {
        Schema::table('anomaly_verifications', function (Blueprint $table) {
            $table->dropColumn('rappel_at');
        });
    }
};
