<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('emergency_contacts', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('nom');
            $table->string('telephone', 20);
            $table->string('relation')->nullable();
            $table->timestamps();
        });

        Schema::create('voice_security_profiles', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->unique()->constrained()->cascadeOnDelete();
            $table->string('mot_securite');
            $table->binary('empreinte_vocale')->nullable();
            $table->boolean('actif')->default(true);
            $table->timestamps();
        });

        Schema::create('emergency_services', function (Blueprint $table) {
            $table->id();
            $table->string('nom');
            $table->string('telephone', 20)->unique();
            $table->string('email')->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('emergency_services');
        Schema::dropIfExists('voice_security_profiles');
        Schema::dropIfExists('emergency_contacts');
    }
};