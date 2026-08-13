<?php

namespace App\Services;

use App\Models\Trip;
use Illuminate\Support\Facades\Http;

class RouteService
{
    /**
     * Calcule l'itinéraire prévu (polyline encodé Google) entre le départ et la
     * destination via OSRM. Repli sur une ligne droite si OSRM indisponible.
     */
    public function plannedRoute(Trip $trip): string
    {
        if ($trip->start_latitude === null || $trip->destination_latitude === null) {
            return '';
        }

        $polyline = $this->fetchOsrmPolyline(
            (float) $trip->start_longitude,
            (float) $trip->start_latitude,
            (float) $trip->destination_longitude,
            (float) $trip->destination_latitude,
        );

        return $polyline ?? $this->encodePolyline([
            [(float) $trip->start_latitude, (float) $trip->start_longitude],
            [(float) $trip->destination_latitude, (float) $trip->destination_longitude],
        ]);
    }

    /**
     * Construit l'itinéraire réel à partir des positions enregistrées (polyline).
     */
    public function actualRoute(Trip $trip): string
    {
        $points = [
            [(float) $trip->start_latitude, (float) $trip->start_longitude],
        ];

        foreach ($trip->locations()->orderBy('captured_at')->get() as $location) {
            $points[] = [(float) $location->latitude, (float) $location->longitude];
        }

        if ($trip->destination_latitude && $trip->destination_longitude) {
            $points[] = [(float) $trip->destination_latitude, (float) $trip->destination_longitude];
        }

        return $this->encodePolyline($points);
    }

    protected function fetchOsrmPolyline(float $fromLng, float $fromLat, float $toLng, float $toLat): ?string
    {
        $base = rtrim(config('services.osrm.base_url'), '/');
        $url = "$base/route/v1/driving/$fromLng,$fromLat;$toLng,$toLat";

        try {
            $response = Http::timeout(3)->get($url, [
                'overview' => 'full',
                'geometries' => 'polyline',
            ]);

            if (! $response->successful()) {
                return null;
            }

            $data = $response->json();
            $geometry = $data['routes'][0]['geometry'] ?? null;

            return is_string($geometry) ? $geometry : null;
        } catch (\Throwable $e) {
            return null;
        }
    }

    /**
     * Encode une liste de points [lat, lng] au format polyline Google.
     */
    public function encodePolyline(array $points): string
    {
        $result = '';
        $prevLat = 0;
        $prevLng = 0;

        foreach ($points as [$lat, $lng]) {
            $latE5 = (int) round($lat * 1e5);
            $lngE5 = (int) round($lng * 1e5);

            $dLat = $latE5 - $prevLat;
            $dLng = $lngE5 - $prevLng;
            $prevLat = $latE5;
            $prevLng = $lngE5;

            $result .= $this->encodeValue($dLat) . $this->encodeValue($dLng);
        }

        return $result;
    }

    protected function encodeValue(int $value): string
    {
        $value = $value < 0 ? ~($value << 1) : ($value << 1);
        $chunk = '';

        while ($value >= 0x20) {
            $chunk .= chr((0x20 | ($value & 0x1f)) + 63);
            $value >>= 5;
        }

        return $chunk . chr($value + 63);
    }
}
