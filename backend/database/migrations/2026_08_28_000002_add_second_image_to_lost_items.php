<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('lost_item_reports', function (Blueprint $table) {
            $table->string('image_url2')->nullable()->after('image_url');
        });
    }

    public function down(): void
    {
        Schema::table('lost_item_reports', function (Blueprint $table) {
            $table->dropColumn('image_url2');
        });
    }
};
