<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('manager_assignments', function (Blueprint $table) {
            $table->id();
            $table->foreignId('manager_id')->constrained('users')->cascadeOnDelete();
            $table->enum('dossier_type', ['OBJET_PERDU', 'LITIGE', 'SOS', 'IDENTITE']);
            $table->unsignedBigInteger('dossier_id');
            $table->enum('statut', ['ATTRIBUE', 'PRIS_EN_CHARGE', 'CLOTURE'])->default('ATTRIBUE');
            $table->timestamp('assigned_at')->useCurrent();
            $table->timestamp('taken_at')->nullable();
            $table->timestamp('closed_at')->nullable();
            $table->timestamps();

            $table->index(['manager_id']);
            $table->index(['dossier_type', 'dossier_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('manager_assignments');
    }
};