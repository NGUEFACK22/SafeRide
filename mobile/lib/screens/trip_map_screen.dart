import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/trip.dart';
import '../services/trip_service.dart';

class TripMapScreen extends StatefulWidget {
  final int tripId;
  final Trip? trip;

  const TripMapScreen({super.key, required this.tripId, this.trip});

  @override
  State<TripMapScreen> createState() => _TripMapScreenState();
}

class _TripMapScreenState extends State<TripMapScreen> {
  final _tripService = TripService();

  bool _loading = true;
  String? _error;
  List<LatLng> _points = [];
  LatLng? _start;
  LatLng? _destination;
  bool _deviationAlert = false;
  double? _deviationKm;

  static const LatLng _fallbackCenter = LatLng(3.8480, 11.5021); // Yaoundé

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _tripService.getRoute(widget.tripId);
      final rawPoints = (data['points'] as List<dynamic>? ?? []);

      final points = rawPoints
          .map((e) => LatLng(
                (e['lat'] as num).toDouble(),
                (e['lng'] as num).toDouble(),
              ))
          .toList();

      LatLng? start;
      if (data['start'] != null) {
        start = LatLng(
          (data['start']['lat'] as num).toDouble(),
          (data['start']['lng'] as num).toDouble(),
        );
      }

      LatLng? destination;
      if (data['destination'] != null) {
        destination = LatLng(
          (data['destination']['lat'] as num).toDouble(),
          (data['destination']['lng'] as num).toDouble(),
        );
      }

      if (!mounted) return;
      setState(() {
        _points = points;
        _start = start;
        _destination = destination;
        _deviationAlert = data['deviation_alert'] == true;
        _deviationKm = (data['deviation_km'] as num?)?.toDouble();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  LatLng get _center {
    if (_points.isNotEmpty) return _points[_points.length ~/ 2];
    if (_start != null) return _start!;
    return _fallbackCenter;
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.trip?.destinationAddress ?? 'Trajet #${widget.tripId}';

    return Scaffold(
      appBar: AppBar(title: Text('Itinéraire · $title')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : Column(
                  children: [
                    if (_deviationAlert)
                      Container(
                        width: double.infinity,
                        color: Colors.orange.shade100,
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded,
                                color: Colors.orange),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Écart d\'itinéraire détecté : '
                                '${_deviationKm?.toStringAsFixed(2) ?? '?'} km',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: FlutterMap(
                        options: MapOptions(
                          initialCenter: _center,
                          initialZoom: 13,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.saferide.saferide_mobile',
                          ),
                          if (_points.length >= 2)
                            PolylineLayer(
                              polylines: [
                                Polyline(
                                  points: _points,
                                  color: Colors.blue,
                                  strokeWidth: 5,
                                ),
                              ],
                            ),
                          MarkerLayer(
                            markers: [
                              if (_start != null)
                                Marker(
                                  point: _start!,
                                  width: 40,
                                  height: 40,
                                  child: const Icon(Icons.location_on,
                                      color: Colors.green, size: 34),
                                ),
                              if (_destination != null)
                                Marker(
                                  point: _destination!,
                                  width: 40,
                                  height: 40,
                                  child: const Icon(Icons.location_on,
                                      color: Colors.red, size: 34),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(4),
                      color: Colors.grey.shade200,
                      child: const Text(
                        'Cartes © OpenStreetMap',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
    );
  }
}