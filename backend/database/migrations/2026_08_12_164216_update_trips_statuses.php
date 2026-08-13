<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::table('trips', function (Blueprint $table) {
            // L'enum statut final est désormais défini dans la migration de création.
            // Ajouter les champs pour l'itinéraire prévu vs réel (compatible PostgreSQL).
            $table->text('planned_route_polyline')->nullable();
            $table->text('actual_route_polyline')->nullable();
            $table->boolean('deviation_alert')->default(false);
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('trips', function (Blueprint $table) {
            $table->dropColumn(['planned_route_polyline', 'actual_route_polyline', 'deviation_alert']);
        });
    }
};
