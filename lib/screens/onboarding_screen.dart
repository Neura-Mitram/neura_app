import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../utils/dialog_utils.dart';
import '../services/translation_service.dart';
import '../utils/restart_utils.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController aiNameController = TextEditingController();
  String selectedVoice = 'male';
  bool isSaving = false;
  String errorMessage = "";
  String selectedLangCode = 'en'; // default
  bool permissionsAccepted = false;
  bool _deniedOnce = false;

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

  late AnimationController _animationController;
  late Animation<double> _glowAnimation;

  Future<void> handleSave() async {
    setState(() {
      isSaving = true;
      errorMessage = "";
    });

    final prefs = await SharedPreferences.getInstance();
    final deviceId = prefs.getString('device_id');

    final aiName = aiNameController.text.trim().isEmpty
        ? 'Neura'
        : aiNameController.text.trim();

    if (deviceId == null) {
      setState(() {
        errorMessage = "⚠️ Device ID not found.";
        isSaving = false;
      });
      return;
    }

    try {
      final response = await AuthService().updateOnboarding(
        deviceId: deviceId,
        aiName: aiName,
        voice: selectedVoice,
        preferredLang: selectedLangCode,
      );

      final actualLang = response['preferred_lang'] ?? selectedLangCode;
      await prefs.setString('preferred_lang', actualLang);

      // ✅ Load translations for preferred language
      await TranslationService.loadTranslations(actualLang);

      // 🛠️ Restart app if RTL directionality changed
      final rtlLangs = ['ar', 'he', 'fa', 'ur'];
      final wasRtl = Directionality.of(context) == TextDirection.rtl;
      final willBeRtl = rtlLangs.contains(actualLang);

      if (wasRtl != willBeRtl) {
        RestartWidget.restartApp(context);
        return;
      }

      await prefs.setString('ai_name', aiName);
      await prefs.setString('voice', selectedVoice);
      await prefs.setBool('onboarding_completed', true);

      // ✅ Step 1: Show instruction as toast/snackbar
      final instructionText = response['wakeword_instruction'];
      final nextstepText = response['next_step'];
      final audioStreamUrl = response['audio_stream_url'];

      if (instructionText != null && audioStreamUrl != null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(instructionText),
              duration: const Duration(seconds: 6),
            ),
          );
        }

        // ✅ Step 2: Play audio stream
        try {
          final player = AudioPlayer(); // from just_audio
          await player.setUrl(audioStreamUrl);
          await player.play(); // async wait until done
          await player.dispose();

          // ✅ Step 3: After playback, show success dialog
          if (context.mounted) {
            await showNeuraSuccessDialog(
              context,
              title: "Welcome, $aiName!",
              subtitle: "You're all set to begin with $nextstepText 🚀",
              buttonText: "Let's Start",
              onButtonTap: () async {
                Navigator.of(context).pop(); // close dialog
                await Future.delayed(const Duration(seconds: 1));
                if (context.mounted) {
                  Navigator.pushReplacementNamed(context, '/wakeword');
                }
              },
            );
          }
        } catch (e) {
          debugPrint("🎧 Failed to play audio stream: $e");
          // fallback: still show success dialog
          if (context.mounted) {
            await showNeuraSuccessDialog(
              context,
              title: "Welcome, $aiName!",
              subtitle: "You're all set to begin with $nextstepText 🚀",
              buttonText: "Let's Start",
              onButtonTap: () async {
                Navigator.of(context).pop();
                if (context.mounted) {
                  Navigator.pushReplacementNamed(context, '/wakeword');
                }
              },
            );
          }
        }
      }
    } catch (e) {
      await showErrorDialog(
        context,
        title: "Something went wrong",
        message: "We couldn't complete onboarding: $e",
      );
    }

    setState(() {
      isSaving = false;
    });
  }

  static Future<void> logoutUser(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (context.mounted) {
      Navigator.pushReplacementNamed(context, '/');
    }
  }

  Future<void> requestNeuraPermissions() async {
    final statuses = await [
      Permission.microphone,
      Permission.location,
      Permission.sms,
      Permission.phone,
      Permission.ignoreBatteryOptimizations,
      Permission.systemAlertWindow,
    ].request();

    final granted = statuses.values.every((s) => s.isGranted || s.isLimited);

    setState(() {
      permissionsAccepted = granted;
      if (!granted) _deniedOnce = true;
    });
  }

  void showNeuraPermissionExplanation() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.lock, color: Colors.red),
            SizedBox(width: 8),
            Text("Neura Needs Permissions"),
          ],
        ),
        content: const SingleChildScrollView(
          child: Text(
            "To work properly, Neura needs the following permissions:\n\n"
            "🎤 Microphone — to hear your voice\n"
            "📍 Location — for emergency SOS and nearby alerts\n"
            "📲 SMS & Phone — to send alerts or call your contacts\n"
            "🔋 Battery Optimization — to run ambient mode without interruption\n"
            "🔔 Overlay — to show the listening dot even when app is closed\n"
            "📶 Internet — for real-time AI streaming and alerts\n\n"
            "Neura never shares your data. These are for your safety and voice support.",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _deniedOnce = true);
              Navigator.pop(context);
            },
            child: const Text("Not Now"),
          ),
          if (_deniedOnce)
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await requestNeuraPermissions();
                if (!permissionsAccepted && context.mounted) {
                  showNeuraPermissionExplanation(); // loop back if still denied
                }
              },
              child: const Text("Retry"),
            ),
          if (_deniedOnce)
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await openAppSettings(); // ✅ requires import from permission_handler
              },
              child: const Text("Open Settings"),
            ),
          ElevatedButton.icon(
            icon: const Icon(Icons.check_circle),
            label: const Text("Allow & Continue"),
            onPressed: () async {
              Navigator.pop(context);
              await requestNeuraPermissions();
            },
          ),
        ],
      ),
    );
  }

  Widget _voiceOption({
    required String imagePath,
    required bool isSelected,
    required VoidCallback onTap,
    required String label,
  }) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              final alpha = (_glowAnimation.value * 255).round();
              return Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: theme.primaryColor.withAlpha(alpha),
                            blurRadius: 30,
                            spreadRadius: 4,
                          ),
                        ]
                      : [],
                  border: Border.all(
                    color: isSelected ? theme.primaryColor : theme.dividerColor,
                    width: 3,
                  ),
                ),
                child: ClipOval(
                  child: Image.asset(
                    imagePath,
                    width: 100,
                    height: 100,
                    fit: BoxFit.cover,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected
                  ? theme
                        .primaryColor // 💙 Solid primary color background
                  : theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected ? theme.primaryColor : theme.dividerColor,
                width: 1.5,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isSelected
                    ? theme
                          .colorScheme
                          .onPrimary // white text on colored background
                    : theme.textTheme.bodyMedium!.color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    aiNameController.text = "Neura";

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _glowAnimation = Tween<double>(
      begin: 0.3,
      end: 0.8,
    ).animate(_animationController);

    if (!permissionsAccepted) {
      Future.delayed(
        const Duration(milliseconds: 500),
        showNeuraPermissionExplanation,
      );
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {},
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          title: Text(
            "Meet Your AI Assistant",
            style: theme.textTheme.titleLarge,
          ),
          backgroundColor: theme.appBarTheme.backgroundColor,
          foregroundColor: theme.appBarTheme.foregroundColor,
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () => logoutUser(context),
              tooltip: "Logout",
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              Text("Set Up Your Neura", style: theme.textTheme.headlineSmall),
              const SizedBox(height: 12),
              Text(
                "Personalize your assistant's name and voice preference.",
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.hintColor,
                ),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: aiNameController,
                decoration: InputDecoration(
                  labelText: "Assistant Name",
                  labelStyle: TextStyle(color: theme.primaryColor),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: theme.primaryColor, width: 2),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: theme.dividerColor),
                  ),
                  prefixIcon: Icon(
                    Icons.person_outline,
                    color: theme.primaryColor,
                  ),
                ),
              ),
              const SizedBox(height: 30),
              Text(
                "Choose Your Assistant's Voice",
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _voiceOption(
                    label: "Male",
                    imagePath: 'assets/avatars/male_listening.png',
                    isSelected: selectedVoice == 'male',
                    onTap: () => setState(() => selectedVoice = 'male'),
                  ),
                  _voiceOption(
                    label: "Female",
                    imagePath: 'assets/avatars/female_listening.png',
                    isSelected: selectedVoice == 'female',
                    onTap: () => setState(() => selectedVoice = 'female'),
                  ),
                ],
              ),
              const SizedBox(height: 40),

              GestureDetector(
                onTap: () async {
                  final selected = await showModalBottomSheet<String>(
                    context: context,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                    ),
                    builder: (_) => ListView(
                      shrinkWrap: true,
                      children: languages.map((lang) {
                        final emoji = getFlagEmojiFromLangCode(lang['code']!);
                        return ListTile(
                          leading: Text(
                            emoji,
                            style: const TextStyle(fontSize: 20),
                          ),
                          title: Text(lang['label']!),
                          onTap: () => Navigator.pop(context, lang['code']),
                        );
                      }).toList(),
                    ),
                  );

                  if (selected != null) {
                    setState(() => selectedLangCode = selected);
                  }
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: "Preferred Language",
                    prefixIcon: const Icon(Icons.language),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    languages.firstWhere(
                      (l) => l['code'] == selectedLangCode,
                    )['label']!,
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
              ),
              const SizedBox(height: 30),
              if (!permissionsAccepted)
                Text(
                  "Please allow permissions to proceed.",
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: (isSaving || !permissionsAccepted)
                      ? null
                      : handleSave,
                  icon: isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.arrow_forward),
                  label: const Text("Continue to Neura"),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(fontSize: 16),
                    backgroundColor: theme.primaryColor,
                    foregroundColor: theme.colorScheme.onPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
