import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';

class TranslationService {
  static Map<String, String> _localizedStrings = {};

  /// Load and cache UI translations for the current user's preferred language
  static Future<void> loadTranslations([String? langCode]) async {
    final prefs = await SharedPreferences.getInstance();
    final lang = langCode ?? prefs.getString('preferred_lang') ?? 'en';
    final keys = _translationKeys;

    final translations = await AuthService().translateUIStrings(
      keys: keys,
      targetLang: lang,  // ✅ Use passed-in language
    );

    _localizedStrings = translations;

    // Cache in SharedPreferences for reuse
    await prefs.setString('cached_translations', jsonEncode(_localizedStrings));
  }

  /// Restore from local cache (e.g., app start)
  static Future<void> restoreCachedTranslations() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('cached_translations');
    if (raw != null) {
      _localizedStrings = Map<String, String>.from(jsonDecode(raw));
    }
  }

  /// Lookup translated string or fallback
  static String tr(String key) => _localizedStrings[key] ?? key;

  /// All Screen UI keys
  static const List<String> _translationKeys = [
    // Chat + Permissions
    "Sending...",
    "❌ Failed",
    "Sent ✅",
    "Emotion: {emotion}",
    "Today",
    "Emergency Alert",
    "Neura detected a dangerous keyword. Do you want to send an SOS alert now?",
    "Cancel",
    "Send SOS",
    "Neura Needs Permissions",
    "To protect you and respond when you talk, Neura needs:\n\n🎤 Microphone — to hear you speak\n📍 Location — to find you during emergencies\n📲 SMS & Calls — to alert your trusted contacts\n\nThese help Neura keep you safe in real-time.",
    "Not Now",
    "Allow & Continue",
    "Some permissions were denied. Neura may not function fully.",
    "Recording...",
    "Ask me anything...",
    "Smart Assistant",

    // Profile Screen
    "Your Profile",
    "Your AI Assistant",
    "Voice: ",
    "Current Plan",
    "Manage Subscription",
    "Log Out",
    "View Insights",
    "Language"

    // Community Reports Screen
    "Community Reports",
    "Toggle My Reports / Community",
    "Search city or reason...",
    "No reports found.",

    // Insights Screen
    "Insights",
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

    // Manage Plan Screen
    "Manage Subscription",
    "Your Current Plan",
    "Downgrade Plan",
    "You can downgrade from Pro to Basic at any time. You will lose Pro features.",
    "Downgrade to Basic",
    "You are not on Pro. Downgrade is not available.",
    "Confirm Downgrade",
    "You will lose:",
    "Unlimited Pro replies",
    "Pro voice styles",
    "Advanced content tools",
    "Cancel",
    "✅ Downgraded to Basic."

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
    "Report Unsafe Area"

    // Report Unsafe Area Screen
    "Report Unsafe Area",
    "Describe the unsafe activity or place:",
    "Enter your report...",
    "Submit Report",
    "✅ Report submitted successfully.",
    "❌ Failed to submit report.",
    "⚠️ Missing token or device ID.",
    "❌ Error: {error}"

    // SOS Alert Screen
    "🚨 Emergency Mode",
    "Neura has detected a distress keyword.",
    "Send SOS Now",
    "⚠️ Missing token or device ID.",
    "✅ SOS backend sent at {timestamp}",
    "❌ Backend SOS failed",
    "❌ Error: {error}",
    "✅ SMS sent to contacts",
    "❌ SMS error: {error}"

    // My SOS Contact Screen
    "My SOS Contacts",
    "❌ Failed to load SOS contacts",
    "❌ Failed to add contact",
    "❌ Failed to delete contact",
    "No contacts added.",
    "Add SOS Contact",
    "Name",
    "Phone",
    "Cancel",
    "Save"

    // Upgrade Screen
    "Upgrade Plan",
    "Your Current Plan",
    "Free",
    "Basic",
    "Pro",
    "Limited access to features.",
    "More features and content.",
    "Full access to everything.",
    "Current Plan",
    "Payment Key",
    "Upgrade Now",
    "✅ Upgrade successful!"

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
  ];

  static String get currentLang {
    final lang = _localizedStrings.keys.isNotEmpty
        ? _localizedStrings.keys.first
        : 'en';
    return lang;
  }

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