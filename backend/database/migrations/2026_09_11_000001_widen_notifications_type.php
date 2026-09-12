<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Élargit notifications.type : le type ANOMALIE_VERIFICATION est utilisé
     * par la détection IA (AiService::createVerification et
     * AnomalyVerificationController::respond) mais n'existait pas dans
     * l'enum d'origine → toute notification d'anomalie échouait
     * silencieusement (try/catch non bloquant dans storeLocation).
     */
    public function up(): void
    {
        Schema::table('notifications', function (Blueprint $table) {
            $table->string('type')->default('SYSTEME')->change();
        });
    }

    public function down(): void
    {
        Schema::table('notifications', function (Blueprint $table) {
            $table->enum('type', ['SOS', 'TRAJET', 'DOSSIER', 'IDENTITE', 'SYSTEME', 'ANOMALIE_VERIFICATION'])->default('SYSTEME')->change();
        });
    }
};