<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('trips', function (Blueprint $table) {
            $table->id();
            $table->foreignId('passager_id')->constrained('users')->cascadeOnDelete();
            $table->foreignId('transporteur_id')->constrained('users')->cascadeOnDelete();
            $table->foreignId('vehicle_id')->constrained()->cascadeOnDelete();
            $table->string('qr_token')->nullable();
            $table->decimal('start_latitude', 10, 7);
            $table->decimal('start_longitude', 10, 7);
            $table->decimal('destination_latitude', 10, 7)->nullable();
            $table->decimal('destination_longitude', 10, 7)->nullable();
            $table->string('destination_address')->nullable();
            $table->timestamp('started_at');
            $table->timestamp('ended_at')->nullable();
            $table->decimal('distance_km', 8, 2)->nullable();
            $table->integer('duration_seconds')->nullable();
            $table->decimal('deviation_km', 8, 2)->nullable();
            $table->enum('statut', [
                'SCANNE',
                'CONFIRME',
                'DESTINATION_PROPOSEE',
                'DESTINATION_CONFIRMEE',
                'EN_COURS',
                'TERMINE',
                'ANNULE',
            ])->default('SCANNE');
            $table->enum('end_method', ['MANUEL', 'AUTO_10MIN'])->nullable();
            $table->timestamps();

            $table->index(['statut']);
            $table->index(['passager_id', 'statut']);
            $table->index(['transporteur_id', 'statut']);
        });

        Schema::create('trip_locations', function (Blueprint $table) {
            $table->id();
            $table->foreignId('trip_id')->constrained()->cascadeOnDelete();
            $table->decimal('latitude', 10, 7);
            $table->decimal('longitude', 10, 7);
            $table->decimal('vitesse_km_h', 5, 2)->nullable();
            $table->timestamp('captured_at');
            $table->timestamps();

            $table->index(['trip_id', 'captured_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('trip_locations');
        Schema::dropIfExists('trips');
    }
};