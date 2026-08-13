<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('lost_item_reports', function (Blueprint $table) {
            $table->id();
            $table->foreignId('trip_id')->constrained()->cascadeOnDelete();
            $table->foreignId('passager_id')->constrained('users')->cascadeOnDelete();
            $table->string('objet');
            $table->text('description')->nullable();
            $table->enum('statut', ['SIGNALE', 'EN_RECHERCHE', 'RETROUVE', 'RESTITUE', 'NON_RETROUVE', 'CLOTURE'])->default('SIGNALE');
            $table->timestamps();

            $table->index(['passager_id', 'statut']);
        });

        Schema::create('disputes', function (Blueprint $table) {
            $table->id();
            $table->foreignId('trip_id')->nullable()->constrained()->nullOnDelete();
            $table->foreignId('passager_id')->constrained('users')->cascadeOnDelete();
            $table->foreignId('transporteur_id')->nullable()->constrained('users')->nullOnDelete();
            $table->string('motif');
            $table->text('description')->nullable();
            $table->text('decision')->nullable();
            $table->enum('statut', ['OUVERT', 'EN_COURS', 'EN_ATTENTE', 'RESOLU', 'CLOTURE'])->default('OUVERT');
            $table->timestamps();

            $table->index(['passager_id', 'statut']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('disputes');
        Schema::dropIfExists('lost_item_reports');
    }
};