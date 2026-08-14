<?php

namespace Database\Seeders;

use App\Models\EmergencyContact;
use App\Models\EmergencyService;
use App\Models\User;
use Illuminate\Database\Seeder;

class EmergencyDataSeeder extends Seeder
{
    public function run(): void
    {
        $services = [
            ['nom' => 'Police Secours', 'telephone' => '117', 'email' => 'police@saferide.demo'],
            ['nom' => 'Gendarmerie', 'telephone' => '113', 'email' => 'gendarmerie@saferide.demo'],
            ['nom' => 'SAMU', 'telephone' => '112', 'email' => 'samu@saferide.demo'],
        ];
        foreach ($services as $s) {
            EmergencyService::firstOrCreate(['telephone' => $s['telephone']], $s);
        }

        $passagers = User::whereHas('roles', fn ($q) => $q->where('slug', 'passager'))->get();
        $samples = [
            ['nom' => 'Famille', 'telephone' => '690111111', 'email' => 'famille@saferide.demo', 'relation' => 'Famille'],
            ['nom' => 'Ami proche', 'telephone' => '690222222', 'email' => 'ami@saferide.demo', 'relation' => 'Ami'],
        ];
        foreach ($passagers as $p) {
            foreach ($samples as $c) {
                EmergencyContact::firstOrCreate(
                    ['user_id' => $p->id, 'nom' => $c['nom']],
                    array_merge($c, ['user_id' => $p->id])
                );
            }
        }
    }
}
