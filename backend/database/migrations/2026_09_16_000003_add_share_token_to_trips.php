<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Suivi GPS partageable : un jeton aléatoire par trajet (share_token),
 * jamais devinable, qui ouvre une page publique de suivi live
 * (/public/suivi/{token}) partagée par le passager ou insérée dans les
 * alertes SOS. Expiration naturelle : la page ne diffuse plus de position
 * dès que le trajet quitte les statuts actifs.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('trips', function (Blueprint $table) {
            $table->string('share_token', 64)->nullable()->unique()->after('qr_token');
        });

        // Jeton des trajets déjà actifs au moment du déploiement
        DB::table('trips')
            ->whereIn('statut', ['SCANNE', 'EN_ATTENTE_TRANSPORTEUR', 'CONFIRME', 'DESTINATION_PROPOSEE', 'DESTINATION_CONFIRMEE', 'EN_COURS'])
            ->whereNull('share_token')
            ->orderBy('id')
            ->chunkById(200, function ($trips) {
                foreach ($trips as $trip) {
                    DB::table('trips')->where('id', $trip->id)
                        ->update(['share_token' => bin2hex(random_bytes(16))]);
                }
            });
    }

    public function down(): void
    {
        Schema::table('trips', function (Blueprint $table) {
            $table->dropUnique(['share_token']);
            $table->dropColumn('share_token');
        });
    }
};
