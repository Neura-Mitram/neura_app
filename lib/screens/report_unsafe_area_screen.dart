import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/api_base.dart';
import '../services/translation_service.dart';

class ReportUnsafeAreaScreen extends StatefulWidget {
  const ReportUnsafeAreaScreen({super.key});

  @override
  State<ReportUnsafeAreaScreen> createState() => _ReportUnsafeAreaScreenState();
}

class _ReportUnsafeAreaScreenState extends State<ReportUnsafeAreaScreen> {
  final TextEditingController _controller = TextEditingController();
  bool isSubmitting = false;
  String? statusMessage;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submitReport() async {
    final reportText = _controller.text.trim();
    if (reportText.isEmpty) return;

    setState(() {
      isSubmitting = true;
      statusMessage = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      final deviceId = prefs.getInt('device_id');

      if (token == null || deviceId == null) {
        setState(
          () => statusMessage = TranslationService.tr(
            "⚠️ Missing token or device ID.",
          ),
        );
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final now = DateTime.now().toIso8601String();

      // 1️⃣ Submit unsafe area report
      final reportUri = Uri.parse("$Baseurl/safety/report-unsafe-area");
      final reportRes = await http.post(
        reportUri,
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
        body: jsonEncode({
          "device_id": deviceId,
          "description": reportText,
          "reason": "user_reported", // or allow user to pick
          "location": "Lat: ${position.latitude}, Lon: ${position.longitude}",
          "latitude": position.latitude,
          "longitude": position.longitude,
          "timestamp": now,
        }),
      );

      // 2️⃣ Also submit cluster ping
      final pingUri = Uri.parse("$Baseurl/safety/cluster-ping");
      await http.post(
        pingUri,
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
        body: jsonEncode({
          "device_id": deviceId,
          "latitude": position.latitude,
          "longitude": position.longitude,
          "timestamp": now,
        }),
      );

      if (reportRes.statusCode == 200) {
        setState(
          () => statusMessage = TranslationService.tr(
            "✅ Report submitted successfully.",
          ),
        );
        _controller.clear();
        Future.delayed(const Duration(seconds: 2), () {
          Navigator.pop(context);
        });
      } else {
        setState(
          () => statusMessage = TranslationService.tr(
            "❌ Failed to submit report.",
          ),
        );
      }
    } catch (e) {
      setState(
        () => statusMessage = TranslationService.tr(
          "❌ Error: {error}",
        ).replaceAll("{error}", "$e"),
      );
    } finally {
      setState(() => isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(TranslationService.tr("Report Unsafe Area")),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Text(
              TranslationService.tr("Describe the unsafe activity or place:"),
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              maxLines: 5,
              decoration: InputDecoration(
                hintText: TranslationService.tr("Enter your report..."),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: isSubmitting ? null : _submitReport,
              icon: const Icon(Icons.report),
              label: Text(TranslationService.tr("Submit Report")),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade900,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
              ),
            ),
            if (statusMessage != null) ...[
              const SizedBox(height: 16),
              Text(
                statusMessage!,
                style: TextStyle(
                  color: statusMessage!.contains("✅")
                      ? Colors.green
                      : Colors.red,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
