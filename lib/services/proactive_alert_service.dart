import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../screens/nearby_sos_screen.dart';
import 'package:vibration/vibration.dart';

class ProactiveAlertService {
  static final _player = AudioPlayer();

  static void handleNearbySosAlert(
    BuildContext context,
    String audioUrl,
  ) async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // 🚨 Snackbar (replacing Fluttertoast)
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          "🚨 Nearby SOS alert received!",
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );

    // 🎯 Vibrate if supported
    if (await Vibration.hasVibrator()) {
      Vibration.vibrate(pattern: [0, 300, 200, 300, 200, 500]);
    }

    // 🔊 Play alert voice
    if (audioUrl.isNotEmpty) {
      try {
        await _player.setUrl(audioUrl);
        _player.play();
      } catch (e) {
        debugPrint("🔇 Audio playback failed: $e");
      }
    }

    // 🔴 Fullscreen overlay
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: isDark
            ? const Color(0xFF000000)
            : const Color(0xFF1A1A1A),
        pageBuilder: (_, __, ___) => const NearbySosScreen(),
      ),
    );
  }
}
