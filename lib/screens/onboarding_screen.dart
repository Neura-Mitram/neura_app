import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../utils/dialog_utils.dart';
import '../utils/restart_utils.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';
import '../widgets/setup_progress_stepper.dart';
import 'package:flutter/services.dart';
import '../services/device_service.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  // Constants
  static const _platformPermission = MethodChannel('com.neura/permissions');
  static const _platformBattery = MethodChannel('com.neura/battery');
  static const _rtlLanguages = {'ar', 'he', 'fa', 'ur'};
  static const _permissionDelay = Duration(milliseconds: 800);
  static const _audioFadeDuration = Duration(milliseconds: 100);
  static const _audioFadeIncrement = 0.1;
  static const _avatarSizeSmall = 80.0;
  static const _avatarSizeLarge = 100.0;

  // State variables
  final TextEditingController _aiNameController = TextEditingController();
  String _selectedVoice = 'male';
  bool _isSaving = false;
  String _selectedLangCode = 'en';
  bool _permissionsAccepted = false;
  bool _deniedOnce = false;
  bool _smartTrackingEnabled = true;
  late AnimationController _animationController;
  late Animation<double> _glowAnimation;

  // Language list
  static const List<Map<String, String>> _languages = [
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

  @override
  void initState() {
    super.initState();
    _aiNameController.text = "Neura";
    
    // Setup animations
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _glowAnimation = Tween<double>(begin: 0.3, end: 0.8).animate(_animationController);
    
    // Show permission explanation after delay
    if (!_permissionsAccepted) {
      Future.delayed(const Duration(milliseconds: 500), _showPermissionExplanation);
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _aiNameController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    setState(() => _isSaving = true);
    showNeuraLoading(context, "Setting up your assistant...");
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final deviceId = prefs.getString('device_id');
      final aiName = _aiNameController.text.trim().isEmpty 
          ? 'Neura' 
          : _aiNameController.text.trim();

      if (deviceId == null) {
        throw Exception("Device ID not found");
      }

      final response = await AuthService().updateOnboarding(
        deviceId: deviceId,
        aiName: aiName,
        voice: _selectedVoice,
        preferredLang: _selectedLangCode,
      );

      final actualLang = response['preferred_lang'] ?? _selectedLangCode;
      await prefs.setString('preferred_lang', actualLang);

      // Handle RTL language change
      final wasRtl = Directionality.of(context) == TextDirection.rtl;
      final willBeRtl = _rtlLanguages.contains(actualLang);
      
      if (wasRtl != willBeRtl) {
        RestartWidget.restartApp(context);
        return;
      }

      // Save preferences
      await prefs.setString('ai_name', aiName);
      await prefs.setString('voice', _selectedVoice);
      await prefs.setBool('smart_tracking_enabled', _smartTrackingEnabled);

      // Play welcome audio
      final audioStreamUrl = response['audio_stream_url'];
      if (audioStreamUrl != null) {
        await _playWelcomeAudio(audioStreamUrl);
      }

      // Show success dialog
      if (context.mounted) {
        await _showSuccessDialog(aiName, response['next_step'] ?? "start exploring");
      }
    } catch (e) {
      if (context.mounted) {
        await showErrorDialog(
          context,
          title: "Setup Error",
          message: "We couldn't complete onboarding: ${e.toString()}",
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _playWelcomeAudio(String url) async {
    final player = AudioPlayer();
    try {
      await player.setVolume(0.0);
      await player.setUrl(url);
      await player.play();
      
      // Fade in audio
      await _fadeInAudio(player);
      
      // Wait for completion
      await player.playbackEventStream.firstWhere(
        (event) => event.processingState == ProcessingState.completed,
      );
    } catch (e) {
      debugPrint("Audio playback error: $e");
    } finally {
      await player.dispose();
    }
  }

  Future<void> _fadeInAudio(AudioPlayer player) async {
    double volume = 0.0;
    while (volume < 1.0) {
      volume = (volume + _audioFadeIncrement).clamp(0.0, 1.0);
      await player.setVolume(volume);
      await Future.delayed(_audioFadeDuration);
    }
  }

  Future<void> _showSuccessDialog(String aiName, String nextStep) async {
    await showNeuraSuccessDialog(
      context,
      title: "Welcome, $aiName!",
      subtitle: "You're all set to $nextStep 🚀",
      buttonText: "Let's Start",
      onButtonTap: () async {
        Navigator.of(context).pop();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('onboarding_completed', true);
        if (context.mounted) {
          Navigator.pushReplacementNamed(context, '/sos-contact');
        }
      },
    );
  }

  Future<void> _requestPermissions() async {
  // Step 1: Core permissions
  final coreStatuses = await [
    Permission.microphone,
    Permission.location,
    Permission.notification, // Added notification permission
    Permission.systemAlertWindow,
  ].request();

  final coreGranted = coreStatuses.values.every((s) => s.isGranted || s.isLimited);
  
  // Step 2: Background location (Android 10+)
  if (coreGranted) {
    await _requestBackgroundLocation();
  }

  // Step 3: Usage access
  bool usageGranted = await _hasUsageAccess();
  if (!usageGranted && context.mounted) {
    await _showUsageAccessDialog();
    // 🔹 Re-check after dialog returns
    usageGranted = await _hasUsageAccess();
  }

  // Step 4: Exact alarms (Android 14+)
  if (coreGranted) {
    await _requestExactAlarmPermission();
  }

  // Step 5: Battery optimization
  if (coreGranted && usageGranted && context.mounted) {
    await _requestBatteryOptimization();
  }

  // Step 6: Full-screen intent (Android 10+)
  if (coreGranted) {
    await _requestFullScreenIntent();
  }

  // Update state with latest usageGranted value
  setState(() {
    _permissionsAccepted = coreGranted && usageGranted;
    if (!_permissionsAccepted) _deniedOnce = true;
  });
 }


  Future<void> _requestBackgroundLocation() async {
    if (await Permission.location.isGranted) {
      final status = await Permission.locationAlways.request();
      if (status.isPermanentlyDenied && context.mounted) {
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text("Background Location Required"),
            content: const Text(
              "For travel alerts and safety features, Neura needs access to "
              "your location even when the app is in the background."
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Skip"),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await openAppSettings();
                },
                child: const Text("Enable"),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _requestExactAlarmPermission() async {
    if (Platform.isAndroid && (await DeviceService().sdkVersion) >= 31) {
      final status = await Permission.scheduleExactAlarm.request();
      if (status.isPermanentlyDenied && context.mounted) {
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text("Exact Alarms Required"),
            content: const Text(
              "For reliable reminders and alerts, Neura needs permission to "
              "schedule exact alarms."
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Skip"),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await openAppSettings();
                },
                child: const Text("Enable"),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _requestFullScreenIntent() async {
    if (Platform.isAndroid && (await DeviceService().sdkVersion) >= 29) {
      final status = await Permission.accessMediaLocation.request();
      if (status.isPermanentlyDenied && context.mounted) {
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text("Full-Screen Alerts"),
            content: const Text(
              "To show critical SOS alerts when your phone is locked, "
              "Neura needs full-screen intent permission."
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Skip"),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await openAppSettings();
                },
                child: const Text("Enable"),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _requestBatteryOptimization() async {
    final userAgreed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Background Operation"),
        content: const Text(
          "To ensure Ambient Mode works reliably, Neura needs to stay active "
          "in the background. Allow this?"
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

    if (userAgreed == true) {
      await _requestBatteryExemption();
    }
  }

    Future<void> _showUsageAccessDialog() async {
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("App Access Required"),
        content: const Text(
          "To make Neura context-aware, we need permission to detect which "
          "app you're using (e.g., Spotify, Gmail)."
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.settings),
            label: const Text("Enable Access"),
            onPressed: () async {
              Navigator.pop(context);
              await _openUsageAccessSettings();
  
              if (!context.mounted) return;
  
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    "Open 'Usage Access' and enable Neura, then return here."
                  ),
                  duration: Duration(seconds: 5),
                ),
              );
  
              bool usageGranted = false;
              for (int i = 0; i < 10; i++) {
                await Future.delayed(const Duration(seconds: 1));
                usageGranted = await _hasUsageAccess();
                debugPrint("Re-checking usage access: $usageGranted");
                if (usageGranted) break;
              }
  
              // Save to SharedPreferences so native and Flutter sync
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('flutter.usage_access_granted', usageGranted);
  
              setState(() {
                _permissionsAccepted = usageGranted;
                if (!_permissionsAccepted) _deniedOnce = true;
              });
  
              if (!_permissionsAccepted && context.mounted) {
                _showPermissionExplanation();
              }
            },
          ),
        ],
      ),
    );
  }


  void _showPermissionExplanation() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PermissionExplanationDialog(
        deniedOnce: _deniedOnce,
        onAllowPressed: () async {
          Navigator.pop(context);
          await _requestPermissions();
          if (!_permissionsAccepted && context.mounted) {
            _showPermissionExplanation();
          }
        },
        onSettingsPressed: () async {
          Navigator.pop(context);
          await openAppSettings();
        },
        onPrivacyPolicyPressed: _showPrivacyPolicyDialog,
      ),
    );
  }

  Future<void> _showPrivacyPolicyDialog() async {
    final policyText = await rootBundle.loadString('assets/neura_privacy_policy.txt');
    
    if (!context.mounted) return;
    
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Privacy Policy"),
        content: SizedBox(
          height: 400,
          child: SingleChildScrollView(
            child: Text(policyText),
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

  Future<bool> _hasUsageAccess() async {
    if (await DeviceService().isRunningOnEmulator()) {
      return true; // Skip check on emulator
    }
  
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getBool('flutter.usage_access_granted') ?? false;
      if (stored) {
        debugPrint("Usage access granted (cached in prefs)");
        return true;
      }
  
      final result = await _platformPermission.invokeMethod('hasUsageAccess');
      debugPrint("Native hasUsageAccess returned: $result");
  
      final granted = result == true;
  
      if (granted) {
        await prefs.setBool('flutter.usage_access_granted', true);
      }
  
      return granted;
    } catch (e) {
      debugPrint("Usage access check error: $e");
      return false;
    }
  }


  Future<void> _openUsageAccessSettings() async {
    try {
      await _platformPermission.invokeMethod('openUsageAccess');
    } catch (e) {
      debugPrint("Error opening usage settings: $e");
    }
  }

  Future<void> _requestBatteryExemption() async {
    try {
      await _platformBattery.invokeMethod('requestIgnoreBatteryOptimization');
    } catch (e) {
      debugPrint("Battery exemption error: $e");
    }
  }

  static Future<void> logoutUser(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (context.mounted) {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  String _getFlagEmoji(String langCode) {
    const langToCountry = {
      'en': 'US', 'fr': 'FR', 'es': 'ES', 'de': 'DE', 'hi': 'IN',
      'zh': 'CN', 'ja': 'JP', 'ko': 'KR', 'ar': 'SA', 'pt': 'PT',
      'ru': 'RU', 'it': 'IT', 'nl': 'NL', 'tr': 'TR', 'pl': 'PL',
      'sv': 'SE', 'fi': 'FI', 'cs': 'CZ', 'bg': 'BG', 'uk': 'UA',
      'el': 'GR', 'id': 'ID', 'vi': 'VN', 'ta': 'IN', 'fil': 'PH',
      'ms': 'MY', 'sk': 'SK', 'no': 'NO', 'ro': 'RO', 'hu': 'HU',
      'hr': 'HR', 'da': 'DK',
    };

    final countryCode = langToCountry[langCode] ?? 'UN';
    return countryCode.codeUnits
        .map((u) => String.fromCharCode(u + 127397))
        .join();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSmallScreen = MediaQuery.of(context).size.width < 360;
    final avatarSize = isSmallScreen ? _avatarSizeSmall : _avatarSizeLarge;
  
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          title: Text("Meet Your AI Assistant", style: theme.textTheme.titleLarge),
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () => logoutUser(context),
              tooltip: "Logout",
            ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SetupProgressStepper(currentStep: SetupStep.onboarding),
                      const SizedBox(height: 24),
  
                      Text(
                        "Set Up Your Neura",
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontSize: isSmallScreen ? 20 : null
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
  
                      Text(
                        "Personalize your assistant's name and voice",
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.hintColor,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
  
                      TextField(
                        controller: _aiNameController,
                        decoration: InputDecoration(
                          labelText: "Assistant Name",
                          prefixIcon: const Icon(Icons.person_outline),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 30),
  
                      Text("Choose Your Assistant's Voice", style: theme.textTheme.titleMedium),
                      const SizedBox(height: 16),
  
                      Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        alignment: WrapAlignment.center,
                        children: [
                          _buildVoiceOption(
                            context: context,
                            label: "Male",
                            imagePath: 'assets/avatars/male_listening.png',
                            isSelected: _selectedVoice == 'male',
                            onTap: () => setState(() => _selectedVoice = 'male'),
                            size: avatarSize,
                          ),
                          _buildVoiceOption(
                            context: context,
                            label: "Female",
                            imagePath: 'assets/avatars/female_listening.png',
                            isSelected: _selectedVoice == 'female',
                            onTap: () => setState(() => _selectedVoice = 'female'),
                            size: avatarSize,
                          ),
                        ],
                      ),
                      const SizedBox(height: 40),
  
                      _buildLanguagePicker(context),
                      const SizedBox(height: 30),
  
                      SwitchListTile(
                        value: _smartTrackingEnabled,
                        onChanged: (value) => setState(() => _smartTrackingEnabled = value),
                        title: const Text("Enable Smart Detect Mode"),
                        subtitle: const Text(
                          "Allow Neura to detect which app you're using for context-aware assistance",
                          style: TextStyle(fontSize: 12),
                        ),
                        activeColor: theme.primaryColor,
                      ),
                      const SizedBox(height: 20),
  
                      if (!_permissionsAccepted)
                        Text(
                          "Please allow permissions to proceed",
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      const SizedBox(height: 16),
  
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _isSaving || !_permissionsAccepted ? null : _handleSave,
                          icon: _isSaving
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: theme.colorScheme.onPrimary,
                                  ),
                                )
                              : const Icon(Icons.arrow_forward),
                          label: const Text("Continue to Neura"),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }


  Widget _buildVoiceOption({
    required BuildContext context,
    required String label,
    required String imagePath,
    required bool isSelected,
    required VoidCallback onTap,
    required double size,
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
                  boxShadow: isSelected ? [
                    BoxShadow(
                      color: theme.primaryColor.withAlpha(alpha),
                      blurRadius: 30,
                      spreadRadius: 4,
                    ),
                  ] : [],
                  border: Border.all(
                    color: isSelected ? theme.primaryColor : theme.dividerColor,
                    width: 3,
                  ),
                ),
                child: ClipOval(
                  child: Image.asset(
                    imagePath,
                    width: size,
                    height: size,
                    fit: BoxFit.cover,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected ? theme.primaryColor : theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected ? theme.primaryColor : theme.dividerColor,
                width: 1.5,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? theme.colorScheme.onPrimary : theme.textTheme.bodyMedium?.color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguagePicker(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final selected = await showModalBottomSheet<String>(
          context: context,
          builder: (_) => ListView(
            shrinkWrap: true,
            children: _languages.map((lang) {
              return ListTile(
                leading: Text(_getFlagEmoji(lang['code']!), style: const TextStyle(fontSize: 24)),
                title: Text(lang['label']!),
                onTap: () => Navigator.pop(context, lang['code']),
              );
            }).toList(),
          ),
        );

        if (selected != null) {
          setState(() => _selectedLangCode = selected);
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: "Preferred Language",
          prefixIcon: const Icon(Icons.language),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(
          _languages.firstWhere((l) => l['code'] == _selectedLangCode)['label']!,
        ),
      ),
    );
  }
}

class _PermissionExplanationDialog extends StatelessWidget {
  final bool deniedOnce;
  final VoidCallback onAllowPressed;
  final VoidCallback onSettingsPressed;
  final VoidCallback onPrivacyPolicyPressed;

  const _PermissionExplanationDialog({
    required this.deniedOnce,
    required this.onAllowPressed,
    required this.onSettingsPressed,
    required this.onPrivacyPolicyPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.lock, color: Colors.red, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Neura Needs Permissions",
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          content: const SingleChildScrollView(
            child: Text(
              "To work properly, Neura needs these permissions:\n\n"
              "🎙️ Microphone — Hear and respond to your voice commands\n\n"
              "🗺️ Location — Enable SOS and travel alerts\n"
              "📍 Background Location — Keep alerts active even when closed\n\n"
              "⏰ Exact Alarms — Deliver reminders right on time\n\n"
              "📲 App Usage Access — Assist you based on your activity\n\n"
              "🔋 Battery Optimization — Stay active in Ambient Mode\n\n"
              "🟢 Overlay Permission — Show listening dot anytime\n\n"
              "🔔 Notifications — Send SOS alerts and important updates\n\n"
              "📟 Full-Screen Alerts — Display urgent SOS messages instantly\n\n"
              "Neura never shares your data. Everything is encrypted for your safety.",
            ),
          ),
          actions: [
            TextButton(
              onPressed: onPrivacyPolicyPressed,
              child: const Text("Privacy Policy"),
            ),
            TextButton(
              onPressed: onSettingsPressed,
              child: const Text("Not Now"),
            ),
            if (deniedOnce)
              TextButton(
                onPressed: onSettingsPressed,
                child: const Text("Open Settings"),
              ),
            FilledButton.icon(
              icon: const Icon(Icons.check_circle),
              label: const Text("Allow & Continue"),
              onPressed: onAllowPressed,
            ),
          ],
        ),
      ),
    );
  }
}
