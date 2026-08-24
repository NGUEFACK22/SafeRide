<?php

use App\Http\Controllers\AdminController;
use App\Http\Controllers\Auth\AuthController;
use App\Http\Controllers\DisputeController;
use App\Http\Controllers\EmergencyContactController;
use App\Http\Controllers\IdentityController;
use App\Http\Controllers\LostItemController;
use App\Http\Controllers\ManagerController;
use App\Http\Controllers\NotificationController;
use App\Http\Controllers\PushTokenController;
use App\Http\Controllers\SosController;
use App\Http\Controllers\TripController;
use App\Http\Controllers\VehicleController;
use App\Http\Controllers\VoiceSecurityProfileController;
use App\Http\Controllers\AiController;
use App\Http\Controllers\RatingController;
use App\Http\Controllers\TransporteurController;
use Illuminate\Support\Facades\Route;

Route::prefix('v1')->group(function () {

    // ==== Auth public ====
Route::post('auth/register', [AuthController::class, 'register']);
Route::post('auth/login', [AuthController::class, 'login']);
Route::post('auth/google', [AuthController::class, 'google']);
Route::post('auth/forgot-password', [AuthController::class, 'forgotPassword']);
Route::post('auth/reset-password', [AuthController::class, 'resetPassword']);

    // ==== Routes authentifiées ====
    Route::middleware('auth:sanctum')->group(function () {
        Route::post('auth/logout', [AuthController::class, 'logout']);
        Route::get('auth/profile', [AuthController::class, 'profile']);
        Route::delete('auth/account', [AuthController::class, 'deleteAccount']);

        // Trajets
        Route::get('trips/current', [TripController::class, 'current']);
        Route::post('trips/start', [TripController::class, 'start']);
        Route::post('trips/{trip}/confirm-embarquement', [TripController::class, 'confirmEmbarquement']);
        Route::post('trips/{trip}/destination', [TripController::class, 'setDestination']);
        Route::post('trips/{trip}/confirm-destination', [TripController::class, 'confirmDestination']);
        Route::post('trips/{trip}/update-destination', [TripController::class, 'updateDestination']);
        Route::get('trips/history', [TripController::class, 'history']);
        Route::post('trips/{trip}/locations', [TripController::class, 'storeLocation']);
        Route::post('trips/{trip}/end', [TripController::class, 'end']);
        Route::get('trips/{trip}/route', [TripController::class, 'route']);

        // Véhicules (transporteur)
        Route::get('vehicles', [VehicleController::class, 'index']);
        Route::post('vehicles', [VehicleController::class, 'store']);
        Route::put('vehicles/{vehicle}', [VehicleController::class, 'update']);
        Route::delete('vehicles/{vehicle}', [VehicleController::class, 'destroy']);
        Route::get('vehicles/{vehicle}/qr', [VehicleController::class, 'qr']);
        Route::post('vehicles/{vehicle}/qr/toggle', [VehicleController::class, 'toggleQr']);
        Route::post('vehicles/{vehicle}/qr/refresh', [VehicleController::class, 'refreshQr']);
        Route::post('vehicles/{vehicle}/position', [VehicleController::class, 'position']);

        // Identité
        Route::post('identity/submit', [IdentityController::class, 'submit']);
        Route::get('identity/status', [IdentityController::class, 'status']);

        // SOS — rate limit 5/min anti-spam (P2-15) + anti double 30s dans controller (P2-9)
        Route::post('sos', [SosController::class, 'create'])->middleware('throttle:5,1');
        Route::get('sos/my', [SosController::class, 'myAlerts']);

        // Contacts d'urgence (notifiés lors d'un SOS)
        Route::get('emergency-contacts', [EmergencyContactController::class, 'index']);
        Route::post('emergency-contacts', [EmergencyContactController::class, 'store']);
        Route::put('emergency-contacts/{contact}', [EmergencyContactController::class, 'update']);
        Route::delete('emergency-contacts/{contact}', [EmergencyContactController::class, 'destroy']);

        // Profil vocal (SOS vocal)
        Route::get('voice/profile', [VoiceSecurityProfileController::class, 'show']);
        Route::post('voice/security-word', [VoiceSecurityProfileController::class, 'setSecurityWord']);
        Route::post('voice/enroll', [VoiceSecurityProfileController::class, 'enroll']);

        // Assistant IA (résumés + stats par rôle)
        Route::get('ai/summary', [AiController::class, 'summary']);
        Route::get('ai/weekly', [AiController::class, 'weekly']);
        Route::get('ai/trips/{trip}', [AiController::class, 'tripSummary']);
        Route::get('ai/anomalies', [AiController::class, 'anomalies'])
            ->middleware(['role:gestionnaire,admin']);

        // Incidents
        Route::get('lost-items', [LostItemController::class, 'index']);
        Route::post('lost-items', [LostItemController::class, 'store']);
        Route::put('lost-items/{report}', [LostItemController::class, 'update']);
        Route::get('lost-items/{report}/chronology', [LostItemController::class, 'chronology']);
        Route::get('disputes', [DisputeController::class, 'index']);
        Route::post('disputes', [DisputeController::class, 'store']);

        // Gestionnaire
        Route::prefix('manager')->middleware(['role:gestionnaire,admin'])->group(function () {
            Route::get('dashboard', [ManagerController::class, 'dashboard']);
            Route::get('assignments', [ManagerController::class, 'myAssignments']);
            Route::post('assignments/{assignment}/take', [ManagerController::class, 'take']);
            Route::post('assignments/{assignment}/close', [ManagerController::class, 'close']);
        });

        // Vérifications d'identité (gestionnaire/admin)
        Route::middleware(['role:gestionnaire,admin'])->group(function () {
            Route::get('identity/pending', [IdentityController::class, 'pending']);
            Route::put('identity/{verification}/review', [IdentityController::class, 'review']);
        });

        // SOS résolution (gestionnaire/admin)
        Route::middleware(['role:gestionnaire,admin'])->group(function () {
            Route::get('sos/{sos}', [SosController::class, 'show']);
            Route::put('sos/{sos}/resolve', [SosController::class, 'resolve']);
        });

        // Notifications (in-app, temps réel par polling)
        Route::get('notifications', [NotificationController::class, 'index']);
        Route::get('notifications/unread-count', [NotificationController::class, 'unreadCount']);
        Route::post('notifications/read-all', [NotificationController::class, 'markAllRead']);
        Route::post('notifications/{notification}/read', [NotificationController::class, 'markRead']);

        // Notation des trajets (1-5 étoiles + commentaire)
        Route::post('trips/{trip}/rate', [RatingController::class, 'store']);
        Route::put('trips/{trip}/rate', [RatingController::class, 'update']);
        Route::get('trips/{trip}/ratings', [RatingController::class, 'index']);
        Route::get('ratings/received', [RatingController::class, 'received']);
        Route::get('ratings/given', [RatingController::class, 'given']);
        Route::get('users/{user}/ratings/stats', [RatingController::class, 'stats']);

        // Transporteur — tableau de bord
        Route::get('transporteur/dashboard', [TransporteurController::class, 'dashboard'])
            ->middleware(['role:transporteur,admin']);

        // Token push FCM (Firebase Cloud Messaging)
        Route::post('push-token', [PushTokenController::class, 'store']);

        // Administration
        Route::prefix('admin')->middleware(['role:admin'])->group(function () {
            Route::get('dashboard', [AdminController::class, 'dashboard']);
            Route::post('users', [AdminController::class, 'createUser']);
            Route::get('users', [AdminController::class, 'listUsers']);
            Route::post('users/{user}/toggle-suspension', [AdminController::class, 'toggleSuspension']);
            Route::get('managers/stats', [AdminController::class, 'managerStats']);
            Route::get('managers/{manager}/stats', [AdminController::class, 'statsByManager']);
        });
    });
});