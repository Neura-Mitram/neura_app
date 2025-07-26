import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/tier_service.dart';
import '../services/translation_service.dart';

class UpgradeScreen extends StatefulWidget {
  const UpgradeScreen({super.key});

  @override
  State<UpgradeScreen> createState() => _UpgradeScreenState();
}

class _UpgradeScreenState extends State<UpgradeScreen> {
  String selectedTier = "basic";
  String paymentKey = "";
  bool isLoading = false;
  String? currentTier;

  final Map<String, Map<String, String>> planInfo = {
    'free': {'desc': "Starter plan with minimal limits.", 'price': "Free"},
    'basic': {'desc': "Limited features with monthly cap.", 'price': "₹19/mo"},
    'pro': {
      'desc': "Unlimited access with priority support.",
      'price': "₹199/mo",
    },
  };

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

  Future<void> handleUpgrade() async {
    setState(() {
      isLoading = true;
    });

    final prefs = await SharedPreferences.getInstance();
    final deviceId = prefs.getString('device_id') ?? "";

    try {
      await TierService().upgradeTier(
        deviceId: deviceId,
        newTier: selectedTier,
        paymentKey: paymentKey,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(TranslationService.tr("✅ Upgrade successful!")),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.tr(
                "❌ Error: {error}",
              ).replaceAll("{error}", e.toString()),
            ),
          ),
        );
      });
    }

    setState(() {
      isLoading = false;
    });
  }

  Widget _tierOption(String tier, String label, String description) {
    final theme = Theme.of(context);
    final isSelected = selectedTier == tier;
    final isCurrent = currentTier == tier;

    return GestureDetector(
      onTap: isCurrent
          ? null
          : () {
              setState(() {
                selectedTier = tier;
              });
            },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary.withOpacity(0.1)
              : theme.cardColor,
          border: Border.all(
            color: isSelected ? theme.colorScheme.primary : theme.dividerColor,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              isCurrent ? Icons.check_circle : Icons.radio_button_unchecked,
              color: isCurrent ? theme.colorScheme.primary : theme.hintColor,
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  TranslationService.tr(label),
                  style: theme.textTheme.titleMedium,
                ),
                Text(
                  TranslationService.tr(description),
                  style: theme.textTheme.bodySmall,
                ),
                Text(
                  planInfo[tier]!["price"]!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
                if (isCurrent)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      TranslationService.tr("Current Plan"),
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(TranslationService.tr("Upgrade Plan"))),
      body: SingleChildScrollView(
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
            _tierOption("free", "Free", planInfo["free"]!["desc"]!),
            _tierOption("basic", "Basic", planInfo["basic"]!["desc"]!),
            _tierOption("pro", "Pro", planInfo["pro"]!["desc"]!),
            const SizedBox(height: 20),
            TextField(
              onChanged: (v) => paymentKey = v,
              decoration: InputDecoration(
                labelText: TranslationService.tr("Payment Key"),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: isLoading ? null : handleUpgrade,
              icon: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.upgrade),
              label: Text(TranslationService.tr("Upgrade Now")),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
