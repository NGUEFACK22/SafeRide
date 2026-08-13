<?php

namespace App\Http\Resources;

use Illuminate\Http\Resources\Json\JsonResource;

class TransporteurResource extends JsonResource
{
    /**
     * Limite les données exposées du transporteur au passager.
     */
    public function toArray($request): array
    {
        return [
            'id' => $this->id,
            'nom' => $this->nom,
            'prenom' => $this->prenom,
            'photo_url' => $this->photo_url,
            'statut_verification' => $this->statutVerification(),
        ];
    }
}
