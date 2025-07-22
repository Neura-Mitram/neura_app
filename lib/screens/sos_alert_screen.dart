import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../services/sos_sms_service.dart';
import '../services/api_base.dart';
import '../screens/chat_screen.dart';
import '../services/translation_service.dart';

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

  Future<void> sendSosSmsToContacts() async {
    final smsService = SosSmsService();
    final contacts = ["9876543210", "9998887776"]; // Replace dynamically later
    final message =
        "🚨 Emergency! I need help. Please check my location or call immediately.";

    try {
      await smsService.sendSmsToMultiple(contacts, message);
      setState(
        () => statusMessage = TranslationService.tr("✅ SMS sent to contacts"),
      );
    } catch (e) {
      setState(
        () => statusMessage = TranslationService.tr(
          "❌ SMS error: {error}",
        ).replaceAll("{error}", e.toString()),
      );
    }
  }

  Future<void> _sendTierBasedSms() async {
    try {
      final message = "${widget.message}\nLocation: ${widget.location}";
      final numbers = await _getSavedSosNumbers();

      final smsService = SosSmsService();
      await smsService.sendSmsToMultiple(numbers, message);
    } catch (e) {
      print("❌ Failed to send SMS: $e");
    }
  }

  Future<List<String>> _getSavedSosNumbers() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final deviceId = prefs.getInt('device_id');

    if (token == null || deviceId == null) return [];

    final uri = Uri.parse('$Baseurl/safety/list-sos-contacts');
    final res = await http.post(
      uri,
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      },
      body: jsonEncode({"device_id": deviceId}),
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      final contacts = data['contacts'] as List<dynamic>;
      return contacts.map<String>((c) => c['phone'].toString()).toList();
    } else {
      debugPrint("❌ Failed to fetch SOS contacts: ${res.body}");
      return [];
    }
  }

  Future<void> _startBackgroundRecording() async {
    // Use any recording plugin like flutter_sound or mic_stream
    print("🎤 Background recording started...");

    if (widget.proofLog) {
      print("🛡️ Proof log mode enabled – save this file securely.");
      // Here you can encrypt and upload later
    }
  }

  @override
  Widget build(BuildContext context) {
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
        backgroundColor: Colors.red.shade900,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  TranslationService.tr("🚨 Emergency Mode"),
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  TranslationService.tr(
                    "Neura has detected a distress keyword.",
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, color: Colors.white70),
                ),
                const SizedBox(height: 40),
                ElevatedButton.icon(
                  icon: const Icon(Icons.warning, size: 28),
                  label: Text(TranslationService.tr("Send SOS Now")),
                  onPressed: isSending
                      ? null
                      : () async {
                          await sendSosAlert();
                          await sendSosSmsToContacts();
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.red.shade900,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (statusMessage != null) ...[
                  const SizedBox(height: 24),
                  Text(
                    statusMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();

    if (widget.autoSms) {
      _sendTierBasedSms(); // call this instead of inline code
    }

    if (widget.backgroundMic) {
      _startBackgroundRecording();
    }
  }
}
