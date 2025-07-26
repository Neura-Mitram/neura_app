import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:web_socket_channel/io.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:mic_stream/mic_stream.dart' as mic_stream;
import 'package:just_audio/just_audio.dart' as just_audio;

import '../main.dart';
import '../screens/sos_alert_screen.dart';
import '../services/proactive_alert_service.dart';

class WsService {
  WebSocketChannel? _channel;
  Stream<Uint8List>? _micStream;
  final just_audio.AudioPlayer _player = just_audio.AudioPlayer();
  Timer? _timer;
  bool _shouldReconnect = true;
  final MethodChannel _platform = const MethodChannel('neura/wakeword');

  Future<void> startStreaming(String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString("auth_token") ?? "";

    final headers = {"authorization": "Bearer $token", "x-device-id": deviceId};

    final uri = Uri.parse(
      "wss://byshiladityamallick-neura-smart-assistant.hf.space/ws/audio-stream",
    );
    _channel = IOWebSocketChannel.connect(uri, headers: headers);

    print("🎙️ Connected to /ws/audio-stream");

    // ✅ Acquire WakeLock
    try {
      await _platform.invokeMethod('acquireWakeLock');
    } catch (e) {
      print("⚠️ WakeLock acquire failed: $e");
    }

    _channel!.stream.listen(
      (event) {
        final data = jsonDecode(event);
        // print("📨 Received WebSocket message: $data");

        // ✅ NEW: Voice limit reached — stop mic stream
        if (data['voice_limit_reached'] == true) {
          // print("🚫 Voice limit reached — stopping mic stream");
          // ✅ Play warning voice before stopping
          final url = data['audio_stream_url'];
          if (url != null && url.toString().startsWith("wss://")) {
            _playTtsPlayback(url);
          }

          // ✅ Then stop the mic stream
          stopStreaming();
          return; // don't process anything further
        }

        if (data['trigger_sos_force'] == true) {
          navigatorKey.currentState?.push(
            MaterialPageRoute(
              builder: (_) => SosAlertScreen(
                message: data['sos_message'] ?? 'SOS triggered by keyword.',
                location: data['location'] ?? '',
                autoSms: data['auto_sms'] == true,
                backgroundMic: data['background_mic'] == true,
                proofLog: data['proof_log'] == true,
              ),
            ),
          );
        } else if (data['trigger_sos'] == true) {
          _showSosDialog();
        } else if ((data['reply']?.toString().toLowerCase() ?? '').contains(
          "nearby sos alert",
        )) {
          final audioUrl = data['audio_url'] ?? '';
          if (audioUrl.isNotEmpty && navigatorKey.currentContext != null) {
            ProactiveAlertService.handleNearbySosAlert(
              navigatorKey.currentContext!,
              audioUrl,
            );
          }
        }

        // ✅ Handle TTS playback
        if (data['audio_stream_url'] != null &&
            data['audio_stream_url'].toString().startsWith("wss://")) {
          final url = data['audio_stream_url'];
          final isForeground =
              WidgetsBinding.instance.lifecycleState ==
              AppLifecycleState.resumed;

          if (isForeground) {
            _playTtsPlayback(url);
          } else {
            const platform = MethodChannel('neura/tts');
            platform.invokeMethod('playTtsInBackground', {"url": url});
          }
        } else {
          // print("❌ No audio_stream_url — falling back");
          _playTtsPlaybackFallback("assets/audio/sorry_connection_lost.mp3");

          const platform = MethodChannel('neura/tts');
          platform.invokeMethod('speakNativeTts', {
            "text": "Sorry, I lost connection",
          });
        }
      },
      onError: (e) {
        // print("❌ WebSocket error: $e");
        _reconnect(deviceId);
      },
      onDone: () {
        // print("⚠️ WebSocket closed. Reconnecting...");
        _reconnect(deviceId);
      },
      cancelOnError: true,
    );

    // ✅ Start mic stream
    _micStream = await mic_stream.MicStream.microphone(
      audioSource: mic_stream.AudioSource.DEFAULT,
      sampleRate: 16000,
      channelConfig: mic_stream.ChannelConfig.CHANNEL_IN_MONO,
      audioFormat: mic_stream.AudioFormat.ENCODING_PCM_16BIT,
    );

    _micStream?.listen((data) {
      _channel?.sink.add(data);

      final micLevel = _getAmplitudeFromBytes(data);
      if (_player.playing && micLevel > 0.1) {
        // print("🔇 User spoke while Neura was speaking — interrupting TTS");
        _player.stop();
        _timer?.cancel();
        _timer = null;
      }
    });
  }

  void _reconnect(String deviceId) {
    if (!_shouldReconnect) return;
    Future.delayed(const Duration(seconds: 3), () {
      print("🔁 Reconnecting mic stream...");
      startStreaming(deviceId);
    });
  }

  Future<void> _playTtsPlayback(String url) async {
    try {
      await _player.stop();
      await _player.setVolume(0.0);
      await _player.setUrl(url);
      await _player.load();
      await _player.play();

      _timer?.cancel();
      _timer = Timer.periodic(const Duration(milliseconds: 100), (t) {
        final newVolume = (_player.volume + 0.1).clamp(0.0, 1.0);
        _player.setVolume(newVolume);
        if (newVolume >= 1.0) {
          t.cancel();
          _timer = null;
        }
      });

      print("🔊 JustAudio playing: $url");
    } catch (e) {
      print("❌ Playback error: $e");
    }
  }

  Future<void> _playTtsPlaybackFallback(String assetPath) async {
    try {
      await _player.stop();
      await _player.setAsset(assetPath);
      await _player.load();
      await _player.play();
    } catch (e) {
      print("❌ Fallback audio error: $e");
    }
  }

  void _showSosDialog() {
    showDialog(
      context: navigatorKey.currentContext!,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("Emergency Alert"),
        content: const Text(
          "Neura detected a dangerous keyword. Do you want to send an SOS alert now?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("Cancel"),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.pushNamed(ctx, '/sos-alert');
            },
            icon: const Icon(Icons.warning),
            label: const Text("Send SOS"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade800,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> stopStreaming() async {
    _shouldReconnect = false;
    await _player.stop();
    _timer?.cancel();
    _timer = null;
    await _channel?.sink.close(status.normalClosure);
    _channel = null;

    // ✅ Release WakeLock
    try {
      await _platform.invokeMethod('releaseWakeLock');
    } catch (e) {
      print("⚠️ WakeLock release failed: $e");
    }
  }

  double _getAmplitudeFromBytes(Uint8List bytes) {
    if (bytes.isEmpty) return 0;
    int max = 0;
    for (int i = 0; i < bytes.length - 1; i += 2) {
      int value = (bytes[i + 1] << 8) | bytes[i];
      max = max < value.abs() ? value.abs() : max;
    }
    return max / 32768.0;
  }

  Future<void> playStremOnce(String text, String voiceId, String lang) async {
    final url =
        "wss://byshiladityamallick-neura-smart-assistant.hf.space/ws/stream/elevenlabs"
        "?text=${Uri.encodeComponent(text)}"
        "&voice_id=$voiceId&lang=$lang";

    try {
      await _player.stop(); // ✅ stop any existing stream
      await _player.setUrl(url);
      await _player.load();
      await _player.play();
      print("🎧 TTS playback started for: $text");
    } catch (e) {
      print("❌ TTS playback error: $e");
    }
  }
}
