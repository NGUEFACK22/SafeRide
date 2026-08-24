<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (DB::getDriverName() === 'pgsql') {
            DB::statement("ALTER TABLE identity_verifications DROP CONSTRAINT IF EXISTS identity_verifications_type_check");
            DB::statement("ALTER TABLE identity_verifications ALTER COLUMN type TYPE varchar(50)");
            DB::statement("ALTER TABLE identity_documents DROP CONSTRAINT IF EXISTS identity_documents_type_check");
            DB::statement("ALTER TABLE identity_documents ALTER COLUMN type TYPE varchar(50)");
        } else {
            Schema::table('identity_verifications', function ($table) {
                $table->string('type', 50)->change();
            });
            Schema::table('identity_documents', function ($table) {
                $table->string('type', 50)->change();
            });
        }
    }

    public function down(): void
    {
        // Pas de rollback strict pour le type élargi
    }
};
