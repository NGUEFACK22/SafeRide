<?php

namespace App\Http\Controllers;

use App\Models\Trip;
use App\Models\TripRating;
use App\Models\Vehicle;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class TransporteurController extends Controller
{
    /**
     * Tableau de bord transporteur : stats agrégées
     * GET /transporteur/dashboard (auth, transporteur|admin)
     */
    public function dashboard(Request $request): JsonResponse
    {
        $user = $request->user();

        $tripsQ = Trip::where('transporteur_id', $user->id);
        $vehiclesCount = Vehicle::where('transporteur_id', $user->id)->count();

        $total = (clone $tripsQ)->count();
        $termine = (clone $tripsQ)->where('statut', 'TERMINE')->count();
        $enCours = (clone $tripsQ)->where('statut', 'EN_COURS')->count();
        $scanne = (clone $tripsQ)->whereIn('statut', ['SCANNE','CONFIRME','DESTINATION_PROPOSEE'])->count();

        $distance = round((float) (clone $tripsQ)->where('statut','TERMINE')->sum('distance_km') ?? 0, 2);
        $passagersDistinct = (clone $tripsQ)->distinct('passager_id')->count('passager_id');
        $ecarts = (clone $tripsQ)->where('deviation_alert', true)->count();
        $dureeMoy = (clone $tripsQ)->where('statut','TERMINE')->avg('duration_seconds');
        $dureeMoy = $dureeMoy ? round((float)$dureeMoy / 60, 1) : 0; // minutes

        $ratingsQ = TripRating::where('rated_id', $user->id);
        $ratingsCount = $ratingsQ->count();
        $ratingsAvg = $ratingsCount ? round((float)$ratingsQ->avg('rating'), 2) : 0;
        $distribution = [];
        for ($i=1; $i<=5; $i++) {
            $distribution[(string)$i] = (clone $ratingsQ)->where('rating', $i)->count();
        }

        $recentTrips = (clone $tripsQ)->with(['passager','vehicle'])->latest()->limit(5)->get();
        $recentRatings = (clone $ratingsQ)->with(['rater','trip'])->latest()->limit(5)->get();

        return response()->json([
            'vehicles_count' => $vehiclesCount,
            'trips' => [
                'total' => $total,
                'termine' => $termine,
                'en_cours' => $enCours,
                'en_attente' => $scanne,
            ],
            'passagers_distinct' => $passagersDistinct,
            'distance_totale_km' => $distance,
            'duree_moy_minutes' => $dureeMoy,
            'ecarts_alert' => $ecarts,
            'ratings' => [
                'count' => $ratingsCount,
                'average' => $ratingsAvg,
                'distribution' => $distribution,
                'recent' => $recentRatings,
            ],
            'recent_trips' => $recentTrips,
        ]);
    }
}
