import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import '../main.dart'; // for navigatorKey
import '../screens/nearby_sos_screen.dart';
import 'api_base.dart';

class ClusterAlertService {
  static Future<void> checkForNearbyUnsafePings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) return;

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final uri = Uri.parse(
        '$Baseurl/safety/nearby-pings?latitude=${position.latitude}&longitude=${position.longitude}',
      );

      final res = await http.get(
        uri,
        headers: {"Authorization": "Bearer $token"},
      );

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final count = data["count"] ?? 0;

        if (count >= 2) {
          final context = navigatorKey.currentContext;
          if (context != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  "⚠️ Multiple nearby users reported unsafe area.",
                  style: TextStyle(color: Colors.white),
                ),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
              ),
            );

            navigatorKey.currentState?.push(
              PageRouteBuilder(
                opaque: false,
                barrierColor: Colors.black.withOpacity(0.5),
                pageBuilder: (_, __, ___) => const NearbySosScreen(),
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint("❌ Error checking unsafe cluster: $e");
    }
  }
}
