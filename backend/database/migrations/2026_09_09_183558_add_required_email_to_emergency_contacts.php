<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // Les contacts d'urgence doivent toujours avoir un email :
        // c'est le canal de notification principal actuellement.
        \App\Models\EmergencyContact::whereNull('email')->orWhere('email', '')->update(['email' => 'contact@saferide.local']);

        Schema::table('emergency_contacts', function (Blueprint $table) {
            $table->string('email', 150)->nullable(false)->change();
        });
    }

    public function down(): void
    {
        Schema::table('emergency_contacts', function (Blueprint $table) {
            $table->string('email', 150)->nullable()->change();
        });
    }
};