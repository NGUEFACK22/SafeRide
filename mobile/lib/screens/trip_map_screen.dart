import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
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
  final _mapController = MapController();

  bool _loading = true;
  String? _error;
  List<LatLng> _points = [];
  LatLng? _start;
  LatLng? _destination;
  bool _deviationAlert = false;
  double? _deviationKm;
  LatLng? _userLocation;
  bool _locating = false;

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

      LatLng? user;
      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
        );
        user = LatLng(position.latitude, position.longitude);
      } catch (_) {
        user = null;
      }

      if (!mounted) return;
      setState(() {
        _points = points;
        _start = start;
        _destination = destination;
        _deviationAlert = data['deviation_alert'] == true;
        _deviationKm = (data['deviation_km'] as num?)?.toDouble();
        _userLocation = user;
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

  Future<void> _centerOnUser() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      final loc = LatLng(position.latitude, position.longitude);
      if (!mounted) return;
      setState(() => _userLocation = loc);
      _mapController.move(loc, 15);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Localisation indisponible')),
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  LatLng get _center {
    if (_userLocation != null) return _userLocation!;
    if (_points.isNotEmpty) return _points[_points.length ~/ 2];
    if (_start != null) return _start!;
    return _fallbackCenter;
  }

  double get _zoom => _userLocation != null ? 15 : 13;

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
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: _center,
                          initialZoom: _zoom,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.tech.saveride',
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
                              if (_userLocation != null)
                                Marker(
                                  point: _userLocation!,
                                  width: 22,
                                  height: 22,
                                  alignment: Alignment.center,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.blue,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: Colors.white, width: 3),
                                      boxShadow: [
                                        BoxShadow(
                                          blurRadius: 6,
                                          color: Colors.black38,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
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
      floatingActionButton: FloatingActionButton.small(
        onPressed: _centerOnUser,
        tooltip: 'Ma position',
        child: _locating
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.my_location),
      ),
    );
  }
}