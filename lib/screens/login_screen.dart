import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:math';
import '../services/auth_service.dart';
import '../services/device_service.dart';
import 'package:just_audio/just_audio.dart';
import '../utils/dialog_utils.dart';
import '../widgets/setup_progress_stepper.dart';

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
    final hasPlayed = prefs.getBool('login_welcome_played') ?? false;

    if (!hasPlayed) {
      await prefs.setBool('login_welcome_played', true);

      try {
        final player = AudioPlayer();
        await player.setVolume(1.0);
        await player.setAsset('assets/audio/welcome_neura.wav');
        await Future.delayed(Duration(milliseconds: 100));
        player.play(); // not awaited
        debugPrint("🎧 Welcome voice started.");
      } catch (e) {
        debugPrint("❌ Playback error: $e");
      }
    }
  }

  @override
  void initState() {
    super.initState();

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
    _playWelcomeMessageIfFirstTime();
  }

  @override
  void dispose() {
    final player = AudioPlayer();
    player.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> handleAnonymousLogin() async {
    showNeuraLoading(context, "Logging you in...");

    final prefs = await SharedPreferences.getInstance();
    final deviceId = await DeviceService().getDeviceId();
    await prefs.setString('device_id', deviceId);

    try {
      await AuthService().anonymousLogin(deviceId);
    } catch (e) {
      Navigator.of(context).pop();
      showNeuraError(context, "Login failed. Please try again.\nError: $e");
      return;
    }

    try {
      final fcmToken = await FirebaseMessaging.instance.getToken();

      if (fcmToken != null) {
        await prefs.setString('last_fcm_token', fcmToken);

        await DeviceService().updateDeviceContextWithFcm(
          fcmToken: fcmToken,
          outputAudioMode: "speaker",
          preferredDeliveryMode: "text",
        );

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("✅ Device registered successfully."),
              duration: Duration(seconds: 2),
              backgroundColor:
                  Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
          );
        }
      } else {
        debugPrint("⚠️ FCM token is null. Device context not updated.");
      }
    } catch (e) {
      debugPrint("⚠️ Device update failed: $e");
    }

    if (context.mounted) {
      await showNeuraSuccessDialog(
        context,
        title: "Neura Activated!",
        subtitle: "Let’s personalize your assistant 🤖",
        buttonText: "Continue",
        onButtonTap: () async {
          Navigator.of(context).pop();
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
    final screenWidth = MediaQuery.of(context).size.width;
    final logoSize = screenWidth * 0.45;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SetupProgressStepper(currentStep: SetupStep.login),
                      const SizedBox(height: 32),
                      Container(
                        width: logoSize,
                        height: logoSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: theme.colorScheme.primary.withAlpha(153),
                              blurRadius: 50,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: Image.asset(
                            'assets/splash/neura_logo.png',
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(height: 40),
                      Text(
                        "🙏 Welcome to",
                        style: theme.textTheme.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      const AnimatedSmriti(),
                      const SizedBox(height: 50),
                      FadeTransition(
                        opacity: _fadeAnimation,
                        child: SlideTransition(
                          position: _slideAnimation,
                          child: Container(
                            decoration: BoxDecoration(
                              boxShadow: [
                                BoxShadow(
                                  color: theme.colorScheme.primary.withOpacity(0.4),
                                  blurRadius: 20,
                                  spreadRadius: 1,
                                ),
                              ],
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: ElevatedButton(
                              onPressed: handleAnonymousLogin,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: theme.colorScheme.primary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30),
                                ),
                              ),
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
                      ),
                      const SizedBox(height: 20),
                      if (message.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12.0),
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 6,
                            children: [
                              Icon(
                                Icons.warning,
                                color: theme.colorScheme.error,
                                size: 20,
                              ),
                              Text(
                                message,
                                style: TextStyle(color: theme.colorScheme.error),
                                textAlign: TextAlign.center,
                              ),
                            ],
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
}

class AnimatedSmriti extends StatefulWidget {
  const AnimatedSmriti({super.key});

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
                        color: theme.colorScheme.primary.withOpacity(0.6),
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
            showLatin ? "Neura Mitram" : "न्यूर मित्रम्:।",
            key: ValueKey(showLatin),
            style: theme.textTheme.titleLarge?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}
