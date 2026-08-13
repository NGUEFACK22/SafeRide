<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('ai_reports', function (Blueprint $table) {
            $table->id();
            $table->enum('type', ['RESUME_TRAJET', 'STATISTIQUES', 'ANOMALIE', 'RECOMMANDATION']);
            $table->text('contenu');
            $table->foreignId('user_id')->nullable()->constrained()->nullOnDelete();
            $table->foreignId('trip_id')->nullable()->constrained()->nullOnDelete();
            $table->string('generateur')->default('IA_SafeRide');
            $table->timestamps();

            $table->index(['user_id']);
            $table->index(['trip_id']);
        });

        Schema::create('ai_insights', function (Blueprint $table) {
            $table->id();
            $table->foreignId('ai_report_id')->constrained()->cascadeOnDelete();
            $table->string('titre');
            $table->text('description')->nullable();
            $table->enum('gravite', ['INFO', 'MOYENNE', 'ELEVEE'])->default('INFO');
            $table->timestamps();

            $table->index(['ai_report_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('ai_insights');
        Schema::dropIfExists('ai_reports');
    }
};