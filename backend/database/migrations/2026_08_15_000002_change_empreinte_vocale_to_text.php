<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('voice_security_profiles', function (Blueprint $table) {
            $table->text('empreinte_vocale')->nullable()->change();
        });
    }

    public function down(): void
    {
        Schema::table('voice_security_profiles', function (Blueprint $table) {
            $table->binary('empreinte_vocale')->nullable()->change();
        });
    }
};