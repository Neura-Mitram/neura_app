import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';

class TranslationService {
  static Map<String, String> _localizedStrings = {};
  static String _currentLang = 'en'; // default

  /// Load and cache UI translations for the current user's preferred language
  static Future<void> loadTranslations([String? langCode]) async {
    final prefs = await SharedPreferences.getInstance();
    final lang = langCode ?? prefs.getString('preferred_lang') ?? 'en';
    final keys = _translationKeys;

    final translations = await AuthService().translateUIStrings(
      keys: keys,
      targetLang: lang, // ✅ Use passed-in language
    );

    _localizedStrings = translations;
    _currentLang = lang;

    // Cache in SharedPreferences for reuse
    await prefs.setString('cached_translations', jsonEncode(_localizedStrings));
  }

  /// Restore from local cache (e.g., app start)
  static Future<void> restoreCachedTranslations() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('cached_translations');
    final lang = prefs.getString('preferred_lang') ?? 'en';
    if (raw != null) {
      _localizedStrings = Map<String, String>.from(jsonDecode(raw));
      _currentLang = lang;
    }
  }

  /// Lookup translated string or fallback
  static String tr(String key) => _localizedStrings[key] ?? key;

  /// All Screen UI keys
  static const List<String> _translationKeys = [
    // Chat + Permissions
    "Neura’s activated. I’m {name}, with you, always.",
    "Private mode enabled.",
    "Private mode disabled.",
    "Failed to update Private Mode.",
    "Enable Memory?",
    "Disable Memory?",
    "Memory is now ON. Neura will start remembering your conversations to help you better.",
    "Memory is now OFF. Neura will not remember anything from your conversations moving forward.",
    "Cancel",
    "OK",
    "Memory enabled.",
    "Memory disabled.",
    "Emergency Alert",
    "Neura detected a dangerous keyword. Do you want to send an SOS alert now?",
    "Send SOS",
    "Today",
    "You've reached your monthly limit. Upgrade to continue chatting.",
    "Upgrade",
    "You're nearing your monthly usage limit. Consider upgrading.",
    "Limit Reached",
    "You've hit your monthly usage limit. Upgrade to continue.",
    "Ask me anything...",
    "Recording...",
    "Toggle Memory",
    "Private Mode",
    "Interpreter ON",
    "Interpreter OFF",
    "Mano-Mitram",
    "Unmute Nudges",
    "Mute Nudges",
    "Private mode expired",

    // Profile Screen
    "Your Profile",
    "Your AI Assistant",
    "Last Sync",
    "AI Model Version",
    "Memory Enabled",
    "Personality Mode",
    "Language",
    "Voice",
    "Current Plan",
    "Manage Subscription",
    "Memory Settings",
    "View Insights",
    "Log Out",
    "Choose Language",
    "Confirm Language Change",
    "From now onwards, your \"{aiName}\" will chat with you in this language. Do you want to continue?",
    "Cancel",
    "Yes, Change",
    "Language updated successfully. Neura will now assist you in this language.",
    "FREE",
    "BASIC",
    "PRO",

    // Community Reports Screen
    "Community Reports",
    "Toggle My Reports / Community",
    "Search city or reason...",
    "No reports found.",
    "Failed to load community reports",

    // Insights Screen
    "Insights",
    "Export Personality",
    "Snapshot not ready yet",
    "Usage Overview",
    "Text Messages",
    "Voice Messages",
    "Creator Usage",
    "Your Streak",
    "Joined",
    "Emotion Trends (Last 30 Days)",
    "This Month",
    "Last Month",
    "No emotion data available.",
    "Personality Traits",
    "No personality data available.",
    "{count} day streak",

    // Manage Plan Screen
    "Manage Subscription",
    "Your Current Plan",
    "Upgrade to Pro",
    "Downgrade Plan",
    "You can downgrade from Pro to Basic at any time. You will lose Pro features.",
    "Downgrade to Basic",
    "Confirm Downgrade",
    "You will lose:",
    "Unlimited Pro replies",
    "Pro voice styles",
    "Advanced content tools",
    "Cancel",
    "Confirm Downgrade",
    "✅ Successfully downgraded to {tier}.",
    "❌ Failed to save file: {error}",
    "❌ {error}",
    "Text Replies",
    "Voice Replies",
    "Content Tools",
    "Priority Support",
    "Pricing",
    "Feature",
    "Free",
    "Basic",
    "Pro",
    "Starter plan with minimal limits.",
    "Limited features with monthly cap.",
    "Unlimited access with priority support.",
    "UNKNOWN",

    // Memory Screen
    "Memory",
    "Memory Enabled",
    "Enable Memory?",
    "Disable Memory?",
    "Neura will start remembering your conversations.",
    "Neura will stop remembering conversations.",
    "Confirm",
    "Cancel",
    "Memory enabled.",
    "Memory disabled.",
    "Toggle Sort Order",
    "Memory is currently disabled.",
    "Please enable memory from settings.",
    "Enable Memory",
    "Export",
    "Exported Memory",
    "Copy",
    "Share",
    "Save as File",
    "Close",
    "File saved to \$directory", // optional to generalize with {path}
    "Copied to clipboard",
    "Failed to export memory.",
    "Delete Memory",
    "Are you sure you want to delete all saved memory?",
    "Delete",
    "Clear",
    "Memory deleted successfully.",
    "File saved to {path}",

    // Unsafe Reports Screen
    "My Unsafe Reports",
    "Search city or keyword...",
    "No reports yet.",
    "Confirm Delete",
    "Are you sure you want to delete this report?",
    "Cancel",
    "Delete",
    "✅ Report deleted",
    "❌ Failed to delete",
    "Location permission denied",
    "Location permission permanently denied. Please enable it from settings.",
    "Location check failed",
    "No reports nearby",
    "Reports",
    "Jump to nearby reports",

    // Nearby SOS Screen
    "❌ Auto-call failed. Please dial manually.",
    "✅ You’re marked safe",
    "❌ Verification failed",
    "Confirm 'I'm Safe' using biometrics or PIN",
    "⚠️ Unsafe Area Detected",
    "Multiple SOS reports (X) in your area.\nStay alert and avoid unsafe zones.",
    "OK",
    "Auto-calling emergency",
    "Calling in X seconds...",
    "📞 Tap to call manually",
    "❌ Could not launch dialer.",
    "🚨 A Neura user nearby\ntriggered an SOS alert!",
    "Stay alert. Help if safe.",
    "I’m Safe",
    "Call for Help",
    "Report Unsafe Area",

    // Report Unsafe Area Screen
    "Report Unsafe Area",
    "Describe the unsafe activity or place:",
    "Enter your report...",
    "Submit Report",
    "✅ Report submitted successfully.",
    "❌ Failed to submit report.",
    "⚠️ Missing token or device ID.",
    "❌ Error: {error}",

    // SOS Alert Screen
    "🚨 Emergency Mode",
    "Neura has detected a distress keyword.",
    "Send SOS Now",
    "⚠️ Missing token or device ID.",
    "✅ SOS backend sent at {timestamp}",
    "❌ Backend SOS failed",
    "❌ Error: {error}",
    "✅ SMS sent to contacts",
    "❌ SMS error: {error}",
    "📨 Message ready. Please tap Send.",

    // My SOS Contact Screen
    "My SOS Contacts",
    "No contacts added.",
    "Add SOS Contact",
    "Name",
    "Phone",
    "Cancel",
    "Save",
    "Next",
    "You can only save up to 3 SOS contacts.",
    "Please enter both name and phone number.",
    "❌ Failed to load SOS contacts",
    "❌ Failed to add contact",
    "❌ Failed to delete contact",

    // Upgrade Screen
    "Upgrade Plan",
    "Your Current Plan",
    "Free",
    "Basic",
    "Pro",
    "Starter plan with minimal limits.",
    "Limited features with monthly cap.",
    "Unlimited access with priority support.",
    "Current Plan",
    "Payment Key",
    "Upgrade Now",
    "✅ Upgrade successful!",

    // Wakeword Trainer Screen
    "Train Wakeword",
    "Uploading your voice samples...",
    "Say your assistant's name (\${3 - currentStep} left)",
    "Recording...",
    "Record Sample \${currentStep + 1}",
    "Upload Samples",
    "Wakeword Trained!",
    "Your assistant can now recognize your voice 🧠",
    "Continue",
    "Upload failed: {error}",
  ];

  static String get currentLang => _currentLang;
}

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
