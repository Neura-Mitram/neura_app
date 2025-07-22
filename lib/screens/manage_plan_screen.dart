import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/tier_service.dart';
import '../services/api_base.dart';
import '../services/translation_service.dart';

class ManagePlanScreen extends StatefulWidget {
  const ManagePlanScreen({super.key});

  @override
  State<ManagePlanScreen> createState() => _ManagePlanScreenState();
}

class _ManagePlanScreenState extends State<ManagePlanScreen> {
  String? currentTier;
  bool isLoading = false;
  String message = "";

  @override
  void initState() {
    super.initState();
    _loadCurrentTier();
  }

  Future<void> _loadCurrentTier() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      currentTier = prefs.getString('tier') ?? "free";
    });
  }

  Future<void> _downgradeTier() async {
    setState(() {
      isLoading = true;
      message = "";
    });

    final prefs = await SharedPreferences.getInstance();
    final deviceId = prefs.getString('device_id') ?? "";

    try {
      await TierService().downgradeTier(deviceId: deviceId);

      // Refresh profile
      final token = prefs.getString('auth_token');
      final profileRes = await http.post(
        Uri.parse("$Baseurl/auth/profile"),
        headers: {
          'Authorization': "Bearer $token",
          'Content-Type': "application/json",
        },
        body: jsonEncode({"device_id": deviceId}),
      );

      if (profileRes.statusCode == 200) {
        final profile = jsonDecode(profileRes.body);
        await prefs.setString('tier', profile['tier'] ?? "basic");
        await prefs.setString('ai_name', profile['ai_name'] ?? "Neura");
        await prefs.setString('voice', profile['voice'] ?? "female");
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(TranslationService.tr("✅ Downgraded to Basic."))),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() {
        message = "❌ ${e.toString()}";
      });
    }

    setState(() {
      isLoading = false;
    });
  }

  void _confirmDowngrade() {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(TranslationService.tr("Confirm Downgrade")),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("⚠️ ${TranslationService.tr("You will lose:")}"),
              SizedBox(height: 8),
              Text("• ${TranslationService.tr("Unlimited Pro replies")}"),
              Text("• ${TranslationService.tr("Pro voice styles")}"),
              Text("• ${TranslationService.tr("Advanced content tools")}"),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(TranslationService.tr("Cancel")),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _downgradeTier();
              },
              child: Text(TranslationService.tr("Confirm Downgrade")),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(TranslationService.tr("Manage Subscription")),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              TranslationService.tr("Your Current Plan"),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.1),
                border: Border.all(
                  color: theme.colorScheme.primary,
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                currentTier?.toUpperCase() ?? "UNKNOWN",
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (currentTier == "pro")
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    TranslationService.tr("Downgrade Plan"),
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    TranslationService.tr("You can downgrade from Pro to Basic at any time. You will lose Pro features."),
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: isLoading ? null : _confirmDowngrade,
                    icon: isLoading
                        ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                        : const Icon(Icons.arrow_downward),
                    label: Text(TranslationService.tr("Downgrade to Basic")),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              )
            else
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: theme.dividerColor),
                ),
                child: Text(
                  TranslationService.tr("You are not on Pro. Downgrade is not available."),
                  style: TextStyle(fontSize: 14),
                ),
              ),
            const SizedBox(height: 20),
            if (message.isNotEmpty)
              Text(
                message,
                style: TextStyle(
                  color: message.startsWith("✅")
                      ? Colors.green
                      : theme.colorScheme.error,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
