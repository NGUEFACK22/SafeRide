<?php

namespace App\Http\Controllers;

use App\Models\EmergencyContact;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class EmergencyContactController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $contacts = EmergencyContact::where('user_id', $request->user()->id)
            ->orderBy('created_at')
            ->paginate(20);

        return response()->json(['contacts' => $contacts]);
    }

    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'nom' => 'required|string|max:100',
            'telephone' => 'required|string|max:20',
            'relation' => 'nullable|string|max:50',
            'email' => 'required|email|max:150',
            'whatsapp_telephone' => 'nullable|string|max:20',
        ]);

        $contact = EmergencyContact::create([
            'user_id' => $request->user()->id,
            'nom' => $data['nom'],
            'telephone' => $data['telephone'],
            'relation' => $data['relation'] ?? null,
            'email' => $data['email'],
            'whatsapp_telephone' => $data['whatsapp_telephone'] ?? null,
        ]);

        return response()->json([
            'message' => 'Contact d\'urgence ajouté',
            'contact' => $contact,
        ], 201);
    }

    public function update(Request $request, int $id): JsonResponse
    {
        $contact = EmergencyContact::where('id', $id)
            ->where('user_id', $request->user()->id)
            ->firstOrFail();

        $data = $request->validate([
            'nom' => 'sometimes|string|max:100',
            'telephone' => 'sometimes|string|max:20',
            'relation' => 'sometimes|nullable|string|max:50',
            'email' => 'sometimes|required|email|max:150',
            'whatsapp_telephone' => 'sometimes|nullable|string|max:20',
        ]);

        $contact->update($data);

        return response()->json([
            'message' => 'Contact d\'urgence mis à jour',
            'contact' => $contact,
        ]);
    }

    public function destroy(Request $request, int $id): JsonResponse
    {
        $contact = EmergencyContact::where('id', $id)
            ->where('user_id', $request->user()->id)
            ->firstOrFail();

        $contact->delete();

        return response()->json(['message' => 'Contact d\'urgence supprimé']);
    }
}