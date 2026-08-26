<?php

namespace App\Http\Resources;

use Illuminate\Http\Resources\Json\JsonResource;

class TripResource extends JsonResource
{
    /**
     * Expose le passager via PassengerResource (données minimales)
     * afin de ne jamais renvoyer email/téléphone au transporteur.
     */
    public function toArray($request): array
    {
        return [
            'id' => $this->id,
            'statut' => $this->statut,
            'start_latitude' => $this->start_latitude,
            'start_longitude' => $this->start_longitude,
            'destination_latitude' => $this->destination_latitude,
            'destination_longitude' => $this->destination_longitude,
            'destination_address' => $this->destination_address,
            'planned_route_polyline' => $this->planned_route_polyline,
            'actual_route_polyline' => $this->actual_route_polyline,
            'deviation_km' => $this->deviation_km,
            'deviation_alert' => $this->deviation_alert,
            'started_at' => $this->started_at,
            'ended_at' => $this->ended_at,
            'distance_km' => $this->distance_km,
            'duration_seconds' => $this->duration_seconds,
            'end_method' => $this->end_method,
            'passager' => new PassengerResource($this->whenLoaded('passager')),
            'transporteur' => new TransporteurResource($this->whenLoaded('transporteur')),
            'vehicle' => $this->whenLoaded('vehicle'),
            'my_rating' => $this->when(
                $request && $request->user(),
                function () use ($request) {
                    $ratings = $this->relationLoaded('ratings')
                        ? $this->ratings
                        : \App\Models\TripRating::where('trip_id', $this->id)->get();
                    return $ratings->firstWhere('rater_id', $request->user()->id);
                }
            ),
            'ratings_avg' => $this->when(
                true,
                function () {
                    $ratings = $this->relationLoaded('ratings')
                        ? $this->ratings
                        : \App\Models\TripRating::where('trip_id', $this->id)->get();
                    return round((float) $ratings->avg('rating'), 2);
                }
            ),
            'ratings_count' => $this->when(
                true,
                function () {
                    $ratings = $this->relationLoaded('ratings')
                        ? $this->ratings
                        : \App\Models\TripRating::where('trip_id', $this->id)->get();
                    return $ratings->count();
                }
            ),
        ];
    }
}
