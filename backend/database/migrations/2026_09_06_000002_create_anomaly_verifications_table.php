<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('anomaly_verifications', function (Blueprint $table) {
            $table->id();
            $table->foreignId('trip_id')->constrained()->cascadeOnDelete();
            $table->foreignId('user_id')->constrained('users')->cascadeOnDelete();
            $table->string('anomaly_type');
            $table->text('description');
            $table->enum('gravite', ['ELEVEE', 'MOYENNE', 'BASSE'])->default('MOYENNE');
            $table->enum('statut', ['EN_ATTENTE', 'CONFIRMEE', 'ALARME'])->default('EN_ATTENTE');
            $table->timestamp('responded_at')->nullable();
            $table->timestamps();

            $table->index(['user_id', 'statut']);
            $table->index(['trip_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('anomaly_verifications');
    }
};
