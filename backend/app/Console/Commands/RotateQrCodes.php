<?php

namespace App\Console\Commands;

use App\Http\Controllers\VehicleController;
use Illuminate\Console\Command;

class RotateQrCodes extends Command
{
    protected $signature = 'qr:rotate';

    protected $description = 'Régénère automatiquement les QR de plus de 24h (rotation auto)';

    public function handle(): int
    {
        $rotated = app(VehicleController::class)->rotateAllExpired();

        $this->info("QR vérifiés : {$rotated}");

        return Command::SUCCESS;
    }
}