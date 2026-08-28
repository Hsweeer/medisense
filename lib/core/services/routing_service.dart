import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:flutter/foundation.dart';

class RouteData {
  final List<LatLng> points;
  final double distanceKm;
  final double durationMinutes;

  RouteData({required this.points, required this.distanceKm, required this.durationMinutes});
}

class RoutingService {
  RoutingService._();
  static final instance = RoutingService._();

  /// Fetches a real road route using OSRM (Open Source Routing Machine)
  Future<RouteData?> getRoute(LatLng start, LatLng end) async {
    final url = 'https://router.project-osrm.org/route/v1/driving/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?overview=full&geometries=geojson';

    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['routes'] == null || (data['routes'] as List).isEmpty) return null;

        final route = data['routes'][0];
        final geometry = route['geometry']['coordinates'] as List;
        final List<LatLng> points = geometry.map((c) => LatLng(c[1].toDouble(), c[0].toDouble())).toList();
        
        return RouteData(
          points: points,
          distanceKm: (route['distance'] as num).toDouble() / 1000,
          durationMinutes: (route['duration'] as num).toDouble() / 60,
        );
      }
    } catch (e) {
      debugPrint('[RoutingService] Error: $e');
    }
    return null;
  }
}
