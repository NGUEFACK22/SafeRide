<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // Nettoyer les anciennes valeurs non autorisées avant restriction
        // Pour pgsql enum, whereNotIn avec valeur invalide (RECIPISSE etc.) lève "invalid input value for enum"
        // On cast en text pour éviter l'erreur
        $driverTmp = DB::getDriverName();
        if ($driverTmp === 'pgsql') {
            DB::statement("UPDATE identity_verifications SET type = 'CNI' WHERE type::text NOT IN ('CNI', 'PASSEPORT')");
            DB::statement("UPDATE identity_documents SET type = 'CNI' WHERE type::text NOT IN ('CNI', 'PASSEPORT')");
        } else {
            DB::table('identity_verifications')->whereNotIn('type', ['CNI', 'PASSEPORT'])->update(['type' => 'CNI']);
            DB::table('identity_documents')->whereNotIn('type', ['CNI', 'PASSEPORT'])->update(['type' => 'CNI']);
        }

        // Pour PostgreSQL et MySQL : modifier l'enum via raw SQL si possible, sinon laisser la validation applicative faire foi
        $driver = DB::getDriverName();
        if ($driver === 'pgsql') {
            // Postgres : Laravel enum = varchar avec check constraint ; on tente de mettre à jour le constraint
            try {
                DB::statement("ALTER TABLE identity_verifications DROP CONSTRAINT IF EXISTS identity_verifications_type_check");
                DB::statement("ALTER TABLE identity_verifications ADD CONSTRAINT identity_verifications_type_check CHECK (type IN ('CNI', 'PASSEPORT'))");
                DB::statement("ALTER TABLE identity_documents DROP CONSTRAINT IF EXISTS identity_documents_type_check");
                DB::statement("ALTER TABLE identity_documents ADD CONSTRAINT identity_documents_type_check CHECK (type IN ('CNI', 'PASSEPORT'))");
            } catch (\Throwable $e) {
                // Fallback silencieux — la validation applicative restreint déjà à CNI/PASSEPORT
            }
        } elseif ($driver === 'mysql') {
            try {
                DB::statement("ALTER TABLE identity_verifications MODIFY type ENUM('CNI','PASSEPORT') NOT NULL DEFAULT 'CNI'");
                DB::statement("ALTER TABLE identity_documents MODIFY type ENUM('CNI','PASSEPORT') NOT NULL DEFAULT 'CNI'");
            } catch (\Throwable $e) {
            }
        }
    }

    public function down(): void
    {
        $driver = DB::getDriverName();
        if ($driver === 'pgsql') {
            try {
                DB::statement("ALTER TABLE identity_verifications DROP CONSTRAINT IF EXISTS identity_verifications_type_check");
                DB::statement("ALTER TABLE identity_verifications ADD CONSTRAINT identity_verifications_type_check CHECK (type IN ('CNI', 'PASSEPORT', 'AUTRE'))");
                DB::statement("ALTER TABLE identity_documents DROP CONSTRAINT IF EXISTS identity_documents_type_check");
                DB::statement("ALTER TABLE identity_documents ADD CONSTRAINT identity_documents_type_check CHECK (type IN ('CNI', 'PASSEPORT', 'AUTRE'))");
            } catch (\Throwable $e) {}
        } elseif ($driver === 'mysql') {
            try {
                DB::statement("ALTER TABLE identity_verifications MODIFY type ENUM('CNI','PASSEPORT','AUTRE') NOT NULL DEFAULT 'CNI'");
                DB::statement("ALTER TABLE identity_documents MODIFY type ENUM('CNI','PASSEPORT','AUTRE') NOT NULL DEFAULT 'CNI'");
            } catch (\Throwable $e) {}
        }
    }
};
