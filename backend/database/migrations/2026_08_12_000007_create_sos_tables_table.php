<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('sos_alerts', function (Blueprint $table) {
            $table->id();
            $table->foreignId('trip_id')->constrained()->cascadeOnDelete();
            $table->foreignId('passager_id')->constrained('users')->cascadeOnDelete();
            $table->enum('declenchement', ['VOCAL', 'BOUTON']);
            $table->decimal('latitude', 10, 7);
            $table->decimal('longitude', 10, 7);
            $table->timestamp('heure_detection');
            $table->enum('statut', ['DETECTE', 'VERIFICATION', 'DECLENCHE', 'NOTIFIE', 'EN_COURS', 'RESOLU', 'FAUSSE_ALERTE', 'CLOTE'])->default('DETECTE');
            $table->json('details')->nullable();
            $table->timestamps();

            $table->index(['passager_id', 'statut']);
            $table->index(['trip_id']);
        });

        Schema::create('sos_emergency_notifications', function (Blueprint $table) {
            $table->id();
            $table->foreignId('sos_alert_id')->constrained()->cascadeOnDelete();
            $table->foreignId('emergency_service_id')->constrained()->cascadeOnDelete();
            $table->timestamp('notifie_le');
            $table->enum('statut', ['EN_ATTENTE', 'TRANSMISE', 'CONFIRMEE', 'ECHEC'])->default('EN_ATTENTE');
            $table->timestamps();

            $table->index(['sos_alert_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('sos_emergency_notifications');
        Schema::dropIfExists('sos_alerts');
    }
};