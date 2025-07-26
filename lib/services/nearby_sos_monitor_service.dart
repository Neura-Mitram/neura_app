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
    try {
      // 🔔 Haptic alert
      if (await Vibration.hasVibrator()) {
        Vibration.vibrate(duration: 700);
      }

      // 🔊 Audio alert with soft fade-in
      final player = AudioPlayer();
      await player.setVolume(0.0);
      await player.setAsset('assets/sos_soft_alert.mp3');
      await player.play();

      // ✅ Fade in volume gradually
      Timer.periodic(const Duration(milliseconds: 100), (timer) {
        final newVolume = (player.volume + 0.1).clamp(0.0, 1.0);
        player.setVolume(newVolume);
        if (newVolume >= 1.0) timer.cancel();
      });

      // 🔲 Show overlay screen
      navigatorKey.currentState?.push(
        PageRouteBuilder(
          opaque: false,
          barrierColor: Colors.black.withOpacity(0.3),
          pageBuilder: (_, __, ___) => const NearbySosScreen(),
        ),
      );

      // ✅ Auto dispose after completion
      player.playbackEventStream
          .firstWhere(
            (event) => event.processingState == ProcessingState.completed,
          )
          .then((_) => player.dispose());
    } catch (e) {
      debugPrint("⚠️ Alert overlay trigger failed: $e");
    }
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
