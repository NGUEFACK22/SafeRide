<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('identity_verifications', function (Blueprint $table) {
            $table->string('recto_url')->nullable()->after('type');
            $table->string('verso_url')->nullable()->after('recto_url');
            $table->string('selfie_url')->nullable()->after('verso_url');
        });
        // identity_documents garde fichier_url unique par document (on crée 3 documents par vérification)
    }

    public function down(): void
    {
        Schema::table('identity_verifications', function (Blueprint $table) {
            $table->dropColumn(['recto_url', 'verso_url', 'selfie_url']);
        });
        // rien à rollback pour identity_documents
    }
};
