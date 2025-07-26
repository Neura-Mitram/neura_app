import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../utils/dialog_utils.dart';
import '../services/translation_service.dart';
import '../utils/restart_utils.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';
import '../widgets/setup_progress_stepper.dart';
import 'package:flutter/services.dart';

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

  static const platformPermission = MethodChannel('com.neura/permissions');
  static const platformBattery = MethodChannel('com.neura/battery');
  bool smartTrackingEnabled = true; // default to ON

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
      await prefs.setBool('smart_tracking_enabled', smartTrackingEnabled);

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
          final player = AudioPlayer();
          try {
            await player.setVolume(0.0); // start muted
            await player.setUrl(audioStreamUrl);
            await player.play();

            // 🔊 Fade in volume
            Timer.periodic(const Duration(milliseconds: 100), (timer) {
              final newVolume = (player.volume + 0.1).clamp(0.0, 1.0);
              player.setVolume(newVolume);
              if (newVolume >= 1.0) {
                timer.cancel();
              }
            });

            // ✅ Wait for stream to finish
            await player.playbackEventStream.firstWhere(
              (event) => event.processingState == ProcessingState.completed,
            );
          } catch (e) {
            debugPrint("🎧 Failed to play audio stream: $e");
          } finally {
            await player.dispose();
          }

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
                  await prefs.setBool('onboarding_completed', true);
                  Navigator.pushReplacementNamed(context, '/sos-contact');
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
                  await prefs.setBool('onboarding_completed', true);
                  Navigator.pushReplacementNamed(context, '/sos-contact');
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
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  Future<void> requestNeuraPermissions() async {
    // Step 1: Request microphone, location, overlay (but NOT battery yet)
    final statuses = await [
      Permission.microphone,
      Permission.location,
      Permission.systemAlertWindow,
    ].request();

    final basicGranted = statuses.values.every(
      (s) => s.isGranted || s.isLimited,
    );
    final usageGranted = await hasUsageAccess();
    print("🧪 Usage access granted: $usageGranted");

    // Step 2: Show usage access prompt if missing
    if (!usageGranted && context.mounted) {
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("Usage Access Required"),
          content: const Text(
            "To make Neura truly smart, we need permission to detect which app you're using. "
            "This helps Neura assist based on your activity (e.g., Spotify, Gmail). Tap below to enable it.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.open_in_new),
              label: const Text("Open Settings"),
              onPressed: () async {
                Navigator.pop(context);
                await openUsageAccessSettings();
                // 🔁 Re-check usage permission after short delay
                await Future.delayed(const Duration(seconds: 1));
                final usageGranted = await hasUsageAccess();
                print("📦 Usage rechecked after settings: $usageGranted");

                setState(() {
                  permissionsAccepted =
                      usageGranted &&
                      statuses.values.every((s) => s.isGranted || s.isLimited);
                  if (!permissionsAccepted) _deniedOnce = true;
                });

                // Optional: show dialog again if still denied
                if (!permissionsAccepted && context.mounted) {
                  showNeuraPermissionExplanation();
                }
              },
            ),
          ],
        ),
      );
    }

    // Step 3: If core permissions passed, ask about battery optimization
    final allCoreGranted = basicGranted && await hasUsageAccess();

    if (allCoreGranted && context.mounted) {
      final userAgreedBatteryOptOut = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("Allow Background Operation?"),
          content: const Text(
            "To ensure Ambient Mode works reliably, Neura needs to stay active in the background. "
            "Would you like to allow this?\n\n(You’ll be prompted to ignore battery optimization.)",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("No"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Yes"),
            ),
          ],
        ),
      );

      if (userAgreedBatteryOptOut == true) {
        await requestBatteryOptimizationExemption();
      }
    }

    // Step 4: Save final state
    final fullyGranted = basicGranted && await hasUsageAccess();

    setState(() {
      permissionsAccepted = fullyGranted;
      if (!fullyGranted) _deniedOnce = true;
    });
  }

  void showNeuraPermissionExplanation() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 400, // 🔒 limits dialog width to 400px max
          ),
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: const [
                Icon(Icons.lock, color: Colors.red, size: 20),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    "Neura Needs Permissions",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            content: const SingleChildScrollView(
              child: Text(
                "To work properly, Neura needs the following permissions:\n\n"
                "🎤 Microphone — to hear your voice commands\n\n"
                "📍 Location — for safety SOS & travel alerts\n\n"
                "📲 App Access — to assist based on your activity\n\n"
                "🔋 Battery — to stay active in Ambient Mode\n\n"
                "🫧 Overlay — to show the listening dot anytime \n\n"
                "Neura never shares your data. Everything is encrypted for your safety.",
                textAlign: TextAlign.start,
              ),
            ),
            actions: [
              TextButton(
                onPressed: showPrivacyPolicyDialog,
                child: const Text("Privacy Policy"),
              ),
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
                    await openAppSettings(); // opens app settings
                  },
                  child: const Text("Open Settings"),
                ),
              ElevatedButton.icon(
                icon: const Icon(Icons.check_circle),
                label: const Text("Allow & Continue"),
                onPressed: () async {
                  Navigator.pop(context);
                  await requestNeuraPermissions();
                  if (!permissionsAccepted && context.mounted) {
                    showNeuraPermissionExplanation(); // loop if denied
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> showPrivacyPolicyDialog() async {
    final policyText = await rootBundle.loadString(
      'assets/neura_privacy_policy.txt',
    );

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Privacy Policy"),
        content: SizedBox(
          height: 400,
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Text(
              policyText,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("I Agree"),
          ),
        ],
      ),
    );
  }

  Future<bool> hasUsageAccess() async {
    try {
      // ⏱️ Wait a bit to allow permission state to update
      await Future.delayed(const Duration(milliseconds: 800));

      final result = await platformPermission.invokeMethod('hasUsageAccess');
      debugPrint("📦 hasUsageAccess returned: $result");
      return result == true;
    } catch (e) {
      debugPrint("❌ Error checking usage access: $e");
      return false;
    }
  }

  Future<void> openUsageAccessSettings() async {
    try {
      await platformPermission.invokeMethod('openUsageAccess');
    } catch (e) {
      debugPrint("Error opening usage access settings: $e");
    }
  }

  Future<void> requestBatteryOptimizationExemption() async {
    try {
      await platformBattery.invokeMethod('requestIgnoreBatteryOptimization');
    } catch (e) {
      print("⚠️ Failed to request battery exemption: $e");
    }
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
              // 🟢 Stepper added at top
              const SetupProgressStepper(currentStep: SetupStep.onboarding),
              const SizedBox(height: 24),

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
                            style: theme.textTheme.titleLarge,
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
              // 🔽 INSERT HERE 🔽
              SwitchListTile(
                value: smartTrackingEnabled,
                onChanged: (value) {
                  setState(() => smartTrackingEnabled = value);
                },
                title: const Text("Enable Smart Detect Mode"),
                subtitle: const Text(
                  "Allow Neura to detect which app you're using (e.g., Gmail, Spotify) to offer helpful, context-aware replies.",
                  style: TextStyle(fontSize: 12),
                ),
                activeColor: theme.primaryColor,
              ),
              const SizedBox(height: 16),
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
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.onPrimary,
                          ),
                        )
                      : const Icon(Icons.arrow_forward),
                  label: Text(
                    "Continue to Neura",
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onPrimary,
                    ),
                  ),
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
