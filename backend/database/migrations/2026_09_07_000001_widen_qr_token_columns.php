<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // Tokens QR signés = ~340 chars > varchar(255)
        Schema::table('qr_codes', function (Blueprint $table) {
            $table->text('token')->change();
        });
        Schema::table('trips', function (Blueprint $table) {
            $table->text('qr_token')->nullable()->change();
        });
    }

    public function down(): void
    {
        Schema::table('qr_codes', function (Blueprint $table) {
            $table->string('token', 255)->change();
        });
        Schema::table('trips', function (Blueprint $table) {
            $table->string('qr_token', 255)->nullable()->change();
        });
    }
};