import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/translation_service.dart';
import '../services/tier_service.dart';
import '../services/api_base.dart';
import 'upgrade_screen.dart';

class ManageSubscriptionScreen extends StatefulWidget {
  const ManageSubscriptionScreen({super.key});

  @override
  State<ManageSubscriptionScreen> createState() =>
      _ManageSubscriptionScreenState();
}

class _ManageSubscriptionScreenState extends State<ManageSubscriptionScreen> {
  String? currentTier;
  String message = "";
  bool isLoading = false;

  final Map<String, Map<String, String>> planInfo = {
    TranslationService.tr("free"): {
      'desc': TranslationService.tr("Starter plan with minimal limits."),
      TranslationService.tr("price"): TranslationService.tr("free"),
    },
    TranslationService.tr("basic"): {
      'desc': TranslationService.tr("Limited features with monthly cap."),
      TranslationService.tr("price"): "₹19/mo",
    },
    TranslationService.tr("pro"): {
      'desc': TranslationService.tr("Unlimited access with priority support."),
      TranslationService.tr("price"): "₹199/mo",
    },
  };

  @override
  void initState() {
    super.initState();
    _loadTier();

    // ✅ Load translations for preferred language
    WidgetsBinding.instance.addPostFrameCallback((_) {
    TranslationService.loadScreenOnInit(context, "plan", onDone: () {
      setState(() {}); // optional if you want to refresh UI
      });
    });
  }

  Future<void> _loadTier() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      currentTier = prefs.getString("tier") ?? "free";
    });
  }

  String _getTierDescription(String? tier) {
    return TranslationService.tr(
      planInfo[tier?.toLowerCase() ?? "free"]?["desc"] ?? "Unknown tier.",
    );
  }

  Future<void> _confirmDowngrade() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(TranslationService.tr("Confirm Downgrade")),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("\u26a0\ufe0f ${TranslationService.tr("You will lose:")}"),
            const SizedBox(height: 8),
            Text("\u2022 ${TranslationService.tr("Unlimited Pro replies")}"),
            Text("\u2022 ${TranslationService.tr("Pro voice styles")}"),
            Text("\u2022 ${TranslationService.tr("Advanced content tools")}"),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(TranslationService.tr("Cancel")),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(TranslationService.tr("Confirm Downgrade")),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _performDowngrade();
    }
  }

  Future<void> _performDowngrade() async {
    setState(() => isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final deviceId = prefs.getString('device_id') ?? "";

    try {
      await TierService().downgradeTier(deviceId: deviceId);

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
        setState(() {
          currentTier = profile['tier'] ?? "basic";
          message = TranslationService.tr(
            "✅ Successfully downgraded to {tier}.",
          ).replaceFirst("{tier}", "Basic");
        });
      } else {
        throw Exception("Failed to refresh profile.");
      }
    } catch (e) {
      setState(() {
        message = "❌ ${e.toString()}";
      });
    }

    setState(() => isLoading = false);
  }

  TableRow _buildRow(IconData icon, String label, List<String> values) {
    final theme = Theme.of(context);
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Icon(icon, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(label, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
        for (final value in values)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (value != "-" && value != "Free")
                  Icon(
                    Icons.check_circle,
                    size: 14,
                    color: theme.colorScheme.secondary,
                  ),
                const SizedBox(width: 4),
                Text(
                  value,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildPlanComparison() {
    final theme = Theme.of(context);
    return Table(
      border: TableBorder.all(color: theme.dividerColor),
      columnWidths: const {
        0: FlexColumnWidth(2),
        1: FlexColumnWidth(),
        2: FlexColumnWidth(),
        3: FlexColumnWidth(),
      },
      children: [
        TableRow(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
          ),
          children: [
            for (final title in [
              TranslationService.tr("Feature"),
              TranslationService.tr("Free"),
              TranslationService.tr("Basic"),
              TranslationService.tr("Pro"),
            ])
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  title,
                  style: theme.textTheme.labelMedium,
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
        _buildRow(Icons.message, TranslationService.tr("Text Replies"), [
          "10/mo",
          "100/mo",
          "Unlimited",
        ]),
        _buildRow(Icons.mic, TranslationService.tr("Voice Replies"), [
          "5/mo",
          "30/mo",
          "Unlimited",
        ]),
        _buildRow(Icons.smart_toy, TranslationService.tr("Content Tools"), [
          "-",
          "-",
          "Advanced",
        ]),
        _buildRow(Icons.support, TranslationService.tr("Priority Support"), [
          "-",
          "-",
          "Yes",
        ]),
        _buildRow(Icons.credit_card, TranslationService.tr("Pricing"), [
          planInfo["free"]!["price"]!,
          planInfo["basic"]!["price"]!,
          planInfo["pro"]!["price"]!,
        ]),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(TranslationService.tr("Manage Subscription"))),
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
                color: theme.colorScheme.surfaceContainer,
                border: Border.all(
                  color: theme.colorScheme.primary,
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      currentTier?.toUpperCase() ??
                          TranslationService.tr("UNKNOWN"),
                      key: ValueKey(currentTier),
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _getTierDescription(currentTier),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _buildPlanComparison(),
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
                    TranslationService.tr(
                      "You can downgrade from Pro to Basic at any time. You will lose Pro features.",
                    ),
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
                      backgroundColor: theme.colorScheme.error,
                      foregroundColor: theme.colorScheme.onError,
                    ),
                  ),
                ],
              )
            else
              ElevatedButton.icon(
                onPressed: () async {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const UpgradeScreen()),
                  );
                  if (result == true) await _loadTier();
                },
                icon: const Icon(Icons.upgrade),
                label: Text(TranslationService.tr("Upgrade to Pro")),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: theme.colorScheme.secondary,
                  foregroundColor: theme.colorScheme.onError,
                ),
              ),
            const SizedBox(height: 20),
            if (message.isNotEmpty)
              Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: message.startsWith("✅")
                      ? theme.colorScheme.secondary
                      : theme.colorScheme.error,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
