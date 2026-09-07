<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('sos_alerts', function (Blueprint $table) {
            $table->dropForeign(['trip_id']);
        });
        Schema::table('sos_alerts', function (Blueprint $table) {
            $table->foreignId('trip_id')->nullable()->change();
            $table->foreign('trip_id')->references('id')->on('trips')->nullOnDelete();
            $table->string('destination')->nullable()->after('trip_id');
        });
    }

    public function down(): void
    {
        Schema::table('sos_alerts', function (Blueprint $table) {
            $table->dropForeign(['trip_id']);
        });
        Schema::table('sos_alerts', function (Blueprint $table) {
            $table->foreignId('trip_id')->nullable(false)->change();
            $table->foreign('trip_id')->references('id')->on('trips')->cascadeOnDelete();
            $table->dropColumn('destination');
        });
    }
};