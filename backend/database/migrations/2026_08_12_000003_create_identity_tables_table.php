<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('identity_verifications', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->enum('type', ['CNI', 'PASSEPORT'])->default('CNI');
            $table->enum('statut', ['EN_ATTENTE', 'VERIFIE', 'ECHOUE', 'A_EXAMINER'])->default('EN_ATTENTE');
            $table->string('provider_kyc')->nullable();
            $table->timestamp('verifie_le')->nullable();
            $table->timestamps();
        });

        Schema::create('identity_documents', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->foreignId('verification_id')->nullable()->constrained('identity_verifications')->nullOnDelete();
            $table->enum('type', ['CNI', 'PASSEPORT'])->default('CNI');
            $table->string('numero')->nullable();
            $table->string('fichier_url');
            $table->json('ocr_data')->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('identity_documents');
        Schema::dropIfExists('identity_verifications');
    }
};