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

    /**
     * Décode une polyline Google en une liste de points [lat, lng].
     */
    public function decodePolyline(string $encoded): array
    {
        if ($encoded === '') {
            return [];
        }

        $points = [];
        $index = 0;
        $len = strlen($encoded);
        $lat = 0;
        $lng = 0;

        while ($index < $len) {
            foreach (['lat', 'lng'] as $coord) {
                $shift = 0;
                $result = 0;
                do {
                    $b = ord($encoded[$index++]) - 63;
                    $result |= ($b & 0x1f) << $shift;
                    $shift += 5;
                } while ($b >= 0x20);

                $dlat = ($result & 1) ? ~ ($result >> 1) : ($result >> 1);
                $lat += $dlat;

                if ($coord === 'lng') {
                    $lng += $dlat;
                    $points[] = [$lat / 1e5, $lng / 1e5];
                }
            }
        }

        return $points;
    }

    /**
     * Distance en km entre deux points GPS (Haversine).
     */
    public function haversine(float $lat1, float $lng1, float $lat2, float $lng2): float
    {
        $earthRadius = 6371;
        $dLat = deg2rad($lat2 - $lat1);
        $dLng = deg2rad($lng2 - $lng1);

        $a = sin($dLat / 2) ** 2
            + cos(deg2rad($lat1)) * cos(deg2rad($lat2)) * sin($dLng / 2) ** 2;

        return $earthRadius * 2 * atan2(sqrt($a), sqrt(1 - $a));
    }
}
