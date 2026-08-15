<?php

namespace App\Http\Controllers;

use App\Models\FcmToken;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

class PushTokenController extends Controller
{
    public function store(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'token' => 'required|string',
            'device' => 'nullable|string|max:20',
        ]);

        if ($validator->fails()) {
            return response()->json(['message' => 'Données invalides', 'errors' => $validator->errors()], 422);
        }

        FcmToken::updateOrCreate(
            ['token' => $request->string('token')->toString()],
            ['user_id' => $request->user()->id, 'device' => $request->input('device')]
        );

        return response()->json(['message' => 'Token enregistré']);
    }
}