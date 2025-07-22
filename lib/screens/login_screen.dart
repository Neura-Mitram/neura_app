import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';
import '../services/auth_service.dart';
import '../services/device_service.dart';
import 'package:just_audio/just_audio.dart';
import '../utils/dialog_utils.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  bool isLoading = false;
  String message = "";

  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  Future<void> _playWelcomeMessageIfFirstTime() async {
    final prefs = await SharedPreferences.getInstance();
    final hasPlayed = prefs.getBool('welcome_played') ?? false;

    if (!hasPlayed) {
      print(">>> Mark as played");
      await prefs.setBool('welcome_played', true);

      try {
        final player = AudioPlayer();
        await player.setVolume(1.0);
        await player.setAsset('assets/audio/welcome_neura.mp3');
        await player.play();
        print("✅ Playback started.");
      } catch (e) {
        print("❌ Playback error: $e");
      }
    } else {
      print(">>> Already played before");
    }
  }

  @override
  void initState() {
    super.initState();

    // Animation setup
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _controller.forward();

    // Play welcome message if first time
    // Direct call to verify
    _playWelcomeMessageIfFirstTime();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> handleAnonymousLogin() async {
    showNeuraLoading(context, "Logging you in...");

    final prefs = await SharedPreferences.getInstance();

    // GET DEVICE ID
    final deviceId = await DeviceService().getDeviceId();

    // SAVING DEVICE ID FOR ENTIRE APP
    await prefs.setString('device_id', deviceId);

    try {
      // This returns the user map (not void)
      await AuthService().anonymousLogin(deviceId);
    } catch (e) {
      Navigator.of(context).pop(); // dismiss loader
      showNeuraError(context, "Login failed. Please try again.\nError: $e");
      return;
    }

    // ✅ You now have user data
    // You can safely read:
    // user["ai_name"], user["voice"], etc.

    try {
      await DeviceService().updateDeviceContext(
        outputAudioMode: "speaker",
        preferredDeliveryMode: "text",
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✅ Device registered successfully."),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print("⚠️ Device update failed: $e");
    }

    // ✅ Navigate to onboarding
    if (context.mounted) {
      await showNeuraSuccessDialog(
        context,
        title: "Neura Activated!",
        subtitle: "Let’s personalize your assistant 🤖",
        buttonText: "Continue",
        onButtonTap: () async {
          Navigator.of(context).pop(); // close dialog
          await Future.delayed(const Duration(seconds: 2));
          if (context.mounted) {
            Navigator.pushReplacementNamed(context, '/onboarding');
          }
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: theme.primaryColor.withAlpha(153),
                          blurRadius: 50,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/neura_logo.png',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                  Text("Welcome to Neura", style: theme.textTheme.titleLarge),
                  const SizedBox(height: 10),
                  const AnimatedSmriti(),
                  const SizedBox(height: 50),
                  SlideTransition(
                    position: _slideAnimation,
                    child: Container(
                      decoration: BoxDecoration(
                        boxShadow: [
                          BoxShadow(
                            color: theme.primaryColor.withOpacity(0.4),
                            blurRadius: 20,
                            spreadRadius: 1,
                          ),
                        ],
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: ElevatedButton(
                        onPressed: handleAnonymousLogin,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: 14.0,
                            horizontal: 40,
                          ),
                          child: Text("Start Activate Neura"),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (message.isNotEmpty)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.warning,
                          color: theme.colorScheme.error,
                          size: 20,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            message,
                            style: TextStyle(color: theme.colorScheme.error),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  // ... Rest of your button code
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AnimatedSmriti extends StatefulWidget {
  const AnimatedSmriti({Key? key}) : super(key: key);

  @override
  State<AnimatedSmriti> createState() => _AnimatedSmritiState();
}

class _AnimatedSmritiState extends State<AnimatedSmriti> {
  bool showLatin = true;

  @override
  void initState() {
    super.initState();
    _startLoop();
  }

  void _startLoop() async {
    while (mounted) {
      // Wait random duration 1–3 seconds
      await Future.delayed(Duration(seconds: 1 + Random().nextInt(3)));

      if (mounted) {
        setState(() {
          showLatin = !showLatin;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          transitionBuilder: (child, animation) {
            // Slide + scale + fade
            final offsetAnimation = Tween<Offset>(
              begin: const Offset(0.0, 0.5),
              end: Offset.zero,
            ).animate(animation);

            final scaleAnimation = Tween<double>(
              begin: 0.9,
              end: 1.0,
            ).animate(animation);

            return SlideTransition(
              position: offsetAnimation,
              child: ScaleTransition(
                scale: scaleAnimation,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    boxShadow: [
                      BoxShadow(
                        color: theme.primaryColor.withOpacity(0.6),
                        blurRadius: 10 * animation.value,
                        spreadRadius: 1 * animation.value,
                      ),
                    ],
                  ),
                  child: child,
                ),
              ),
            );
          },
          child: Text(
            showLatin ? "Smṛti" : "स्मृति",
            key: ValueKey(showLatin),
            style: theme.textTheme.titleLarge?.copyWith(
              color: theme.primaryColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}
