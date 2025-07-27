import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'manage_subscription_screen.dart';
import 'login_screen.dart';
import 'insights_screen.dart';
import 'memory_screen.dart';
import '../services/community_alert_banner_service.dart';
import '../services/translation_service.dart';
import '../utils/restart_utils.dart';
import 'package:vibration/vibration.dart';
import '../services/auth_service.dart';
import '../services/profile_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String aiName = "Neura";
  String voice = "female";
  String tier = "free";
  String userLastActive = "";
  String modelVersion = "v2.0";
  bool memoryEnabled = false;
  String personalityMode = "default";

  final List<Map<String, String>> languages = [
    {'code': 'ar', 'label': 'العربية'},
    {'code': 'bg', 'label': 'Български'},
    {'code': 'zh', 'label': '中文'},
    {'code': 'hr', 'label': 'Hrvatski'},
    {'code': 'cs', 'label': 'Čeština'},
    {'code': 'da', 'label': 'Dansk'},
    {'code': 'nl', 'label': 'Nederlands'},
    {'code': 'en', 'label': 'English'},
    {'code': 'fil', 'label': 'Filipino'},
    {'code': 'fi', 'label': 'Suomi'},
    {'code': 'fr', 'label': 'Français'},
    {'code': 'de', 'label': 'Deutsch'},
    {'code': 'el', 'label': 'Ελληνικά'},
    {'code': 'hi', 'label': 'हिन्दी'},
    {'code': 'id', 'label': 'Bahasa Indonesia'},
    {'code': 'it', 'label': 'Italiano'},
    {'code': 'ja', 'label': '日本語'},
    {'code': 'ko', 'label': '한국어'},
    {'code': 'ms', 'label': 'Bahasa Melayu'},
    {'code': 'pl', 'label': 'Polski'},
    {'code': 'pt', 'label': 'Português'},
    {'code': 'ro', 'label': 'Română'},
    {'code': 'ru', 'label': 'Русский'},
    {'code': 'sk', 'label': 'Slovenčina'},
    {'code': 'es', 'label': 'Español'},
    {'code': 'sv', 'label': 'Svenska'},
    {'code': 'ta', 'label': 'தமிழ்'},
    {'code': 'tr', 'label': 'Türkçe'},
    {'code': 'uk', 'label': 'Українська'},
    {'code': 'hu', 'label': 'Magyar'},
    {'code': 'no', 'label': 'Norsk'},
    {'code': 'vi', 'label': 'Tiếng Việt'},
  ];

  String getFlagEmojiFromLangCode(String langCode) {
    // Map some language codes to appropriate country codes (ISO Alpha-2)
    const langToCountry = {
      'en': 'US',
      'fr': 'FR',
      'es': 'ES',
      'de': 'DE',
      'hi': 'IN',
      'zh': 'CN',
      'ja': 'JP',
      'ko': 'KR',
      'ar': 'SA',
      'pt': 'PT',
      'ru': 'RU',
      'it': 'IT',
      'nl': 'NL',
      'tr': 'TR',
      'pl': 'PL',
      'sv': 'SE',
      'fi': 'FI',
      'cs': 'CZ',
      'bg': 'BG',
      'uk': 'UA',
      'el': 'GR',
      'id': 'ID',
      'vi': 'VN',
      'ta': 'IN',
      'fil': 'PH',
      'ms': 'MY',
      'sk': 'SK',
      'no': 'NO',
      'ro': 'RO',
      'hu': 'HU',
      'hr': 'HR',
      'da': 'DK',
    };

    final countryCode =
        langToCountry[langCode.toLowerCase()] ?? 'UN'; // fallback: Unknown
    return countryCode.codeUnits
        .map((u) => String.fromCharCode(u + 127397))
        .join();
  }

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final profile = await fetchProfileSummary();
    setState(() {
      aiName = profile["ai_name"] ?? "Neura";
      voice = profile["voice"] ?? "female";
      tier = profile["tier"] ?? "free";
      userLastActive = profile["last_active_at"] ?? "";
      modelVersion = profile["model_version"] ?? "v2.0";
      memoryEnabled = profile["memory_enabled"] ?? false;
      personalityMode = profile["personality_mode"] ?? "default";
    });
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (context.mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  Widget _planBadge(String tier) {
    Color color;
    String label;

    switch (tier) {
      case "pro":
        color = Colors.blue;
        label = "PRO";
        break;
      case "basic":
        color = Colors.orange;
        label = "BASIC";
        break;
      default:
        color = Colors.grey;
        label = "FREE";
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _card({required Widget child}) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withOpacity(0.05),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  void _showLanguagePicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            Text(
              TranslationService.tr("Choose Language"),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Divider(),
            ...languages.map((lang) {
              final emoji = getFlagEmojiFromLangCode(lang['code']!);
              return ListTile(
                leading: Text(emoji, style: const TextStyle(fontSize: 20)),
                title: Text(lang['label']!),
                onTap: () async {
                  Navigator.pop(context); // close picker first

                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) {
                      return AlertDialog(
                        title: Text(
                          TranslationService.tr("Confirm Language Change"),
                        ),
                        content: Text(
                          TranslationService.tr(
                            'From now onwards, your "$aiName" will chat with you in this language. Do you want to continue?',
                          ),
                        ),
                        actions: [
                          TextButton(
                            child: Text(TranslationService.tr("Cancel")),
                            onPressed: () => Navigator.of(context).pop(false),
                          ),
                          ElevatedButton(
                            child: Text(TranslationService.tr("Yes, Change")),
                            onPressed: () => Navigator.of(context).pop(true),
                          ),
                        ],
                      );
                    },
                  );

                  if (confirm != true) return;

                  // 🔄 Save locally
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('preferred_lang', lang['code']!);
                  await TranslationService.loadTranslations(lang['code']!);

                  // 🔗 Update backend
                  await _updatePreferredLangBackend(lang['code']!);

                  final rtlLangs = ['ar', 'he', 'fa', 'ur'];
                  final willBeRtl = rtlLangs.contains(lang['code']);
                  final wasRtl =
                      Directionality.of(context) == TextDirection.RTL;

                  if (willBeRtl != wasRtl) {
                    RestartWidget.restartApp(context);
                    return;
                  }

                  setState(() {});

                  if (await Vibration.hasVibrator()) {
                    Vibration.vibrate(duration: 100);
                  }

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        TranslationService.tr(
                          "Language updated successfully. Neura will now assist you in this language.",
                        ),
                      ),
                      duration: const Duration(seconds: 3),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              );
            }),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  Future<void> _updatePreferredLangBackend(String langCode) async {
    try {
      final response = await AuthService().updateUserLang(
        preferredLang: langCode,
      );
      debugPrint("Success: $response");
    } catch (e) {
      debugPrint("Failed to sync lang to backend: $e");
    }
  }

  String _formatDateTime(String? isoString) {
    if (isoString == null) return "-";
    final dt = DateTime.tryParse(isoString);
    return dt != null ? DateFormat.yMMMd().add_jm().format(dt) : "-";
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(TranslationService.tr("Your Profile"))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const CommunityAlertBanner(),

            // Avatar Card
            _card(
              child: Row(
                children: [
                  ClipOval(
                    child: Image.asset(
                      voice == "male"
                          ? 'assets/avatars/male_listening.png'
                          : 'assets/avatars/female_listening.png',
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(aiName, style: theme.textTheme.titleMedium),
                      Text(
                        TranslationService.tr("Your AI Assistant"),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Sync & Model Card
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "${TranslationService.tr("Last Sync")}: ${_formatDateTime(userLastActive)}",
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "${TranslationService.tr("AI Model Version")}: ${modelVersion.toUpperCase()}",
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),

            // Memory + Personality Card
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "${TranslationService.tr("Memory Enabled")}: ${memoryEnabled ? "Yes" : "No"}",
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "${TranslationService.tr("Personality Mode")}: ${personalityMode.toUpperCase()}",
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),

            // Language Card
            _card(
              child: ListTile(
                leading: const Icon(Icons.language),
                title: Text(TranslationService.tr("Language")),
                subtitle: Text(
                  "${getFlagEmojiFromLangCode(TranslationService.currentLang)} ${languages.firstWhere((lang) => lang['code'] == TranslationService.currentLang, orElse: () => {'label': 'English'})['label']!}",
                ),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: _showLanguagePicker,
              ),
            ),

            // Voice Card
            _card(
              child: Row(
                children: [
                  Icon(Icons.mic, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Text(
                    "${TranslationService.tr("Voice")}: ${voice[0].toUpperCase()}${voice.substring(1)}",
                    style: theme.textTheme.bodyLarge,
                  ),
                ],
              ),
            ),

            // Current Plan
            _card(
              child: Row(
                children: [
                  Icon(
                    Icons.workspace_premium,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(TranslationService.tr("Current Plan")),
                      const SizedBox(height: 4),
                      _planBadge(tier),
                    ],
                  ),
                ],
              ),
            ),

            // Subscription
            _card(
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ManageSubscriptionScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.manage_accounts),
                label: Text(TranslationService.tr("Manage Subscription")),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  minimumSize: const Size.fromHeight(50),
                ),
              ),
            ),

            // Memory Details
            _card(
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          const MemoryScreen(), // 👈 replace with your screen
                    ),
                  );
                },
                icon: const Icon(Icons.memory),
                label: Text(TranslationService.tr("Memory Settings")),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  minimumSize: const Size.fromHeight(50),
                ),
              ),
            ),

            // Insights
            _card(
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const InsightsScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.bar_chart),
                label: Text(TranslationService.tr("View Insights")),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  minimumSize: const Size.fromHeight(50),
                ),
              ),
            ),

            // Logout
            _card(
              child: ElevatedButton.icon(
                onPressed: _logout,
                icon: const Icon(Icons.logout),
                label: Text(TranslationService.tr("Log Out")),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  minimumSize: const Size.fromHeight(50),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
