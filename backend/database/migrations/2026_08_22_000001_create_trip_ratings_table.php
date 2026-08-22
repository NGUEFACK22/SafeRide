<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('trip_ratings', function (Blueprint $table) {
            $table->id();
            $table->foreignId('trip_id')->constrained('trips')->cascadeOnDelete();
            $table->foreignId('rater_id')->constrained('users')->cascadeOnDelete();
            $table->foreignId('rated_id')->constrained('users')->cascadeOnDelete();
            $table->unsignedTinyInteger('rating'); // 1..5
            $table->text('comment')->nullable();
            $table->timestamps();

            $table->unique(['trip_id', 'rater_id']);
            $table->index(['rated_id']);
            $table->index(['trip_id']);
        });

        // Ajout colonnes agrégées optionnelles pour performance (non critique)
        // On ne touche pas à users/trips pour rester minimal
    }

    public function down(): void
    {
        Schema::dropIfExists('trip_ratings');
    }
};
