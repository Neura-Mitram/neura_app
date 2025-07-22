import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:vibration/vibration.dart';
import 'package:just_audio/just_audio.dart';
import '../main.dart';
import '../screens/nearby_sos_screen.dart';
import 'api_base.dart';

class NearbySosMonitorService {
  static Future<void> checkNearbyDanger() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString("token");
      final enabled = prefs.getBool("nearby_monitor_enabled") ?? true;

      if (!enabled || token == null) return;

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final uri = Uri.parse(
        "$Baseurl/safety/nearby-pings?latitude=${position.latitude}&longitude=${position.longitude}",
      );

      final res = await http.get(
        uri,
        headers: {"Authorization": "Bearer $token"},
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if ((data['count'] ?? 0) >= 2) {
          // Trigger warning overlay
          _triggerAlertOverlay();
        }
      }
    } catch (e) {
      debugPrint("NearbySosMonitor error: $e");
    }
  }

  static Future<void> _triggerAlertOverlay() async {
    if (await Vibration.hasVibrator()) {
      Vibration.vibrate(duration: 700);
    }

    final player = AudioPlayer();
    await player.setAsset('assets/sos_soft_alert.mp3');
    player.play();

    navigatorKey.currentState?.push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black.withOpacity(0.3),
        pageBuilder: (_, __, ___) => const NearbySosScreen(),
      ),
    );
  }
}

/// Call this inside main() or after login if enabled
Future<void> initBackgroundMonitoring() async {
  // Schedule every 15 mins using background_fetch / workmanager (plugin setup required)
  // For now, we manually call this from chat loader or home screen periodically
  Timer.periodic(const Duration(minutes: 15), (_) {
    NearbySosMonitorService.checkNearbyDanger();
  });
}
