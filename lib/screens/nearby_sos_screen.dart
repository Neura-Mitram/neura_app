import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:lottie/lottie.dart';
import 'package:vibration/vibration.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/api_base.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import '../services/community_alert_banner_service.dart';
import '../services/translation_service.dart';

class NearbySosScreen extends StatefulWidget {
  const NearbySosScreen({super.key});

  @override
  State<NearbySosScreen> createState() => _NearbySosScreenState();
}

class _NearbySosScreenState extends State<NearbySosScreen> {
  bool isProcessing = false;

  @override
  void initState() {
    super.initState();
    _vibrateDevice();
    Future.delayed(const Duration(seconds: 2), () {
      _autoDialIfTierAllowed();
    });
    _checkUnsafeCluster();
  }

  Future<void> _autoDialIfTierAllowed() async {
    final prefs = await SharedPreferences.getInstance();
    final tier = prefs.getString('tier') ?? 'free';

    if (tier == 'basic' || tier == 'pro') {
      final contacts = prefs.getStringList('sos_contacts');
      String? targetNumber;

      if (contacts != null && contacts.isNotEmpty) {
        try {
          final decoded = json.decode(contacts.first);
          targetNumber = decoded['phone'];
        } catch (_) {}
      }

      targetNumber ??= '112';

      if (targetNumber.isNotEmpty) {
        final result = await FlutterPhoneDirectCaller.callNumber(targetNumber);
        if (result != true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                TranslationService.tr(
                  "❌ Auto-call failed. Please dial manually.",
                ),
                style: const TextStyle(color: Colors.white),
              ),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    }
  }

  Future<void> _vibrateDevice() async {
    if (await Vibration.hasVibrator()) {
      Vibration.vibrate(duration: 500);
    }
  }

  Future<void> _confirmImSafe() async {
    setState(() => isProcessing = true);

    final auth = LocalAuthentication();
    bool authenticated = false;

    try {
      authenticated = await auth.authenticate(
        localizedReason: TranslationService.tr(
          "Confirm 'I'm Safe' using biometrics or PIN",
        ),
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
    } on PlatformException catch (e) {
      debugPrint("Auth error: $e");
    }

    if (authenticated) {
      await _logImSafeToBackend();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            TranslationService.tr("✅ You’re marked safe"),
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            TranslationService.tr("❌ Verification failed"),
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.black,
        ),
      );
    }

    setState(() => isProcessing = false);
  }

  Future<void> _logImSafeToBackend() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final deviceId = prefs.getInt("device_id");
      final token = prefs.getString("token");
      if (deviceId == null || token == null) return;

      final uri = Uri.parse("$Baseurl/safety/im-safe");
      await http.post(
        uri,
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
        body: jsonEncode({
          "device_id": deviceId,
          "status": "safe",
          "timestamp": DateTime.now().toIso8601String(),
        }),
      );
    } catch (e) {
      debugPrint("❌ Error logging safe status: $e");
    }
  }

  Future<void> _checkUnsafeCluster() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final uri = Uri.parse(
        "$Baseurl/safety/nearby-pings?latitude=${position.latitude}&longitude=${position.longitude}",
      );

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString("token");
      final res = await http.get(
        uri,
        headers: {"Authorization": "Bearer $token"},
      );

      if (res.statusCode == 200) {
        final count = jsonDecode(res.body)["count"] ?? 0;
        if (count >= 2) _showClusterWarning(count);
      }
    } catch (e) {
      debugPrint("❌ Cluster check error: $e");
    }
  }

  void _showClusterWarning(int count) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.error,
        title: Text(
          TranslationService.tr("⚠️ Unsafe Area Detected"),
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          TranslationService.tr(
            "Multiple SOS reports ({count}) in your area.",
          ).replaceAll("{count}", "$count"),
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              TranslationService.tr("OK"),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _callEmergencyServices() async {
    final prefs = await SharedPreferences.getInstance();
    final tier = prefs.getString('tier') ?? "free";

    if (tier == 'basic' || tier == 'pro') {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) {
          return StatefulBuilder(
            builder: (context, setState) {
              int seconds = 3;
              Timer.periodic(const Duration(seconds: 1), (t) {
                if (seconds == 1) {
                  t.cancel();
                  Navigator.pop(context);
                  _launchDialer("112");
                } else {
                  setState(() => seconds--);
                }
              });

              return AlertDialog(
                backgroundColor: Theme.of(context).colorScheme.error,
                title: Text(
                  TranslationService.tr("Auto-calling emergency"),
                  style: const TextStyle(color: Colors.white),
                ),
                content: Text(
                  TranslationService.tr("Calling in $seconds seconds..."),
                  style: const TextStyle(color: Colors.white),
                ),
              );
            },
          );
        },
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            TranslationService.tr("📞 Tap to call manually"),
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.orange,
        ),
      );
      _launchDialer("112");
    }
  }

  void _launchDialer(String number) async {
    final url = Uri.parse("tel://$number");
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            TranslationService.tr("❌ Could not launch dialer."),
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  void _reportUnsafeArea() {
    Navigator.pushNamed(context, '/report-unsafe');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.error.withOpacity(0.95),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CommunityAlertBanner(),
              Lottie.asset('assets/neura_alert_ripple.lottie', width: 220),
              const SizedBox(height: 24),
              Text(
                TranslationService.tr(
                  "🚨 A Neura user nearby\ntriggered an SOS alert!",
                ),
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                TranslationService.tr("Stay alert. Help if safe."),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 30),
              ElevatedButton.icon(
                onPressed: isProcessing ? null : _confirmImSafe,
                icon: const Icon(Icons.verified_user),
                label: Text(TranslationService.tr("I’m Safe")),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: theme.colorScheme.error,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _callEmergencyServices,
                icon: const Icon(Icons.phone),
                label: Text(TranslationService.tr("Call for Help")),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _reportUnsafeArea,
                icon: const Icon(Icons.report),
                label: Text(TranslationService.tr("Report Unsafe Area")),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white70),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
