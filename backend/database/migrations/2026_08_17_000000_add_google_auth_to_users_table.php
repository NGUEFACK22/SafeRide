<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            // Un utilisateur Google peut se connecter sans téléphone.
            $table->string('telephone', 20)->nullable()->change();
            $table->string('google_id')->nullable()->unique()->after('telephone');
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropUnique(['google_id']);
            $table->dropColumn('google_id');
            $table->string('telephone', 20)->nullable(false)->change();
        });
    }
};