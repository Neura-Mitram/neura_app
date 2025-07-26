import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:ui';

import '../services/api_base.dart';
import '../screens/chat_screen.dart';
import '../services/translation_service.dart';
import '../services/sos_service.dart';

class SosAlertScreen extends StatefulWidget {
  final String message;
  final String location;
  final bool autoSms;
  final bool backgroundMic;
  final bool proofLog;

  const SosAlertScreen({
    required this.message,
    required this.location,
    this.autoSms = false,
    this.backgroundMic = false,
    this.proofLog = false,
    super.key,
  });

  @override
  State<SosAlertScreen> createState() => _SosAlertScreenState();
}

class _SosAlertScreenState extends State<SosAlertScreen> {
  bool isSending = false;
  String? statusMessage;

  Future<void> sendSosAlert() async {
    setState(() {
      isSending = true;
      statusMessage = null;
    });

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final deviceId = prefs.getString('device_id');

    if (token == null || deviceId == null) {
      setState(
        () => statusMessage = TranslationService.tr(
          "⚠️ Missing token or device ID.",
        ),
      );
      setState(() => isSending = false);
      return;
    }

    final uri = Uri.parse("$Baseurl/sos-alert");

    final payload = {
      "device_id": deviceId,
      "message": widget.message,
      if (widget.location.isNotEmpty) "location": widget.location,
    };

    try {
      final response = await http.post(
        uri,
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
        body: jsonEncode(payload),
      );

      final result = jsonDecode(response.body);

      if (response.statusCode == 200 && result['success'] == true) {
        setState(
          () => statusMessage = TranslationService.tr(
            "✅ SOS backend sent at {timestamp}",
          ).replaceAll("{timestamp}", result['timestamp']),
        );
      } else {
        setState(
          () => statusMessage = TranslationService.tr("❌ Backend SOS failed"),
        );
      }
    } catch (e) {
      setState(
        () => statusMessage = TranslationService.tr(
          "❌ Error: {error}",
        ).replaceAll("{error}", e.toString()),
      );
    } finally {
      setState(() => isSending = false);
    }
  }

  Future<void> _startBackgroundRecording() async {
    // Use any recording plugin like flutter_sound or mic_stream
    debugPrint("🎤 Background recording started...");
    // Will Come next updates

    if (widget.proofLog) {
      debugPrint("🛡️ Proof log mode enabled – save this file securely.");
      // Here you can encrypt and upload later
      // Will Come next updates
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.backgroundMic) {
      _startBackgroundRecording();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: true,
      onPopInvoked: (didPop) {
        if (didPop) {
          final chatState = context.findAncestorStateOfType<ChatScreenState>();
          if (chatState != null) {
            chatState.sosLaunched = false;
          }
        }
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            // 🔴 Blur & dark overlay
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
                child: Container(color: Colors.black.withOpacity(0.6)),
              ),
            ),

            // 🔴 Centered SOS content
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      TranslationService.tr("🚨 Emergency Mode"),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      TranslationService.tr(
                        "Neura has detected a distress keyword.",
                      ),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 40),
                    const SizedBox(height: 16),
                    Text(
                      TranslationService.tr(
                        "Your default SMS app will open with a ready-to-send SOS message.",
                      ),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.sms_rounded, size: 26),
                      label: Text(
                        TranslationService.tr("Send SOS via SMS"),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      onPressed: isSending
                          ? null
                          : () async {
                              await SosService.triggerSafeSms(
                                message: widget.message,
                              );

                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    TranslationService.tr(
                                      "📨 Message ready. Please tap Send.",
                                    ),
                                  ),
                                  backgroundColor: Colors.blueGrey,
                                  duration: const Duration(seconds: 4),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );

                              if (widget.autoSms) await sendSosAlert();
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.redAccent.shade700,
                        shadowColor: Colors.black45,
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 16,
                        ),
                        textStyle: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (statusMessage != null) ...[
                      const SizedBox(height: 24),
                      Text(
                        statusMessage!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
