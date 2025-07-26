import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../screens/nearby_sos_screen.dart';
import 'package:vibration/vibration.dart';

class ProactiveAlertService {
  static final _player = AudioPlayer();

  static Future<void> handleNearbySosAlert(
    BuildContext context,
    String audioUrl,
  ) async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // 🚨 Snackbar alert
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          "🚨 Nearby SOS alert received!",
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 4),
      ),
    );

    // 📳 Vibrate pattern
    if (await Vibration.hasVibrator()) {
      Vibration.vibrate(pattern: [0, 300, 200, 300, 200, 500]);
    }

    // 🔊 Play alert audio with fade-in
    if (audioUrl.isNotEmpty) {
      try {
        await _player.setVolume(0.0);
        await _player.setUrl(audioUrl);
        await _player.play();

        Timer.periodic(const Duration(milliseconds: 100), (timer) {
          final newVolume = (_player.volume + 0.1).clamp(0.0, 1.0);
          _player.setVolume(newVolume);
          if (newVolume >= 1.0) timer.cancel();
        });

        // Dispose after playback
        _player.playbackEventStream
            .firstWhere(
              (event) => event.processingState == ProcessingState.completed,
            )
            .then((_) => _player.dispose());
      } catch (e) {
        debugPrint("🔇 SOS audio playback failed: $e");
        await _player.dispose(); // ensure disposal even on error
      }
    }

    // 🔴 Show full-screen overlay
    final isAlreadyOpen = ModalRoute.of(context)?.isCurrent != true;
    if (!isAlreadyOpen) {
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
}
