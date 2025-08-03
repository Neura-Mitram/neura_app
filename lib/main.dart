import 'package:flutter/material.dart';
import 'package:neura_app/screens/insights_screen.dart';
import 'package:neura_app/screens/manage_subscription_screen.dart';
import 'package:neura_app/screens/sos_contact_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/login_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/upgrade_screen.dart';
import 'screens/onboarding_screen.dart';
import 'theme.dart';
import 'widgets/neura_loader.dart';
import 'screens/report_unsafe_area_screen.dart';
import 'screens/my_unsafe_reports_screen.dart';
import 'screens/sos_alert_screen.dart';
import 'screens/nearby_sos_screen.dart';
import 'screens/community_reports_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/wakeword_trainer_screen.dart';
import 'screens/memory_screen.dart';
import 'utils/restart_utils.dart';
import 'package:flutter/services.dart';
import '../services/ws_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

final platform = MethodChannel('neura/wakeword');
final platformMic = MethodChannel('com.neura/mic_control');
final platformSos = MethodChannel('sos.screen.trigger');


Future<void> stopOverlayDotService() async {
  try {
    await platform.invokeMethod('stopOverlayDotService');
    debugPrint("🛑 OverlayDotService stopped");
  } catch (e) {
    debugPrint("❌ Failed to stop OverlayDotService: $e");
  }
}


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final prefs = await SharedPreferences.getInstance();
  final deviceId = prefs.getString('device_id');
  final tier = prefs.getString('tier') ?? "free";
  final onboardingCompleted = prefs.getBool('onboarding_completed') ?? false;
  final sosContactCompleted = prefs.getBool('sos_contacts_completed') ?? false;
  final wakewordCompleted = prefs.getBool('wakeword_completed') ?? false;

  bool isLoggedIn = deviceId != null && deviceId.isNotEmpty;
  bool needsOnboarding = !onboardingCompleted;
  bool needssosContact = !sosContactCompleted;
  bool needsWakeword = !wakewordCompleted;

  await stopOverlayDotService();
  
  runApp(
    RestartWidget(
      child: NeuraApp(
        isLoggedIn: isLoggedIn,
        userTier: tier,
        needsOnboarding: needsOnboarding,
        needssosContact: needssosContact,
        needsWakeword: needsWakeword,
      ),
    ),
  );

  debugPrint(
    "🧠 deviceId: $deviceId | onboarding: $onboardingCompleted | sos: $sosContactCompleted | wakeword: $wakewordCompleted",
  );


  platformMic.setMethodCallHandler((call) async {
    if (call.method == "startMic") {
      final deviceId = prefs.getString('device_id');
      if (deviceId != null) {
        debugPrint("🎙️ Mic trigger received — launching WsService stream...");
        await WsService().startStreaming(deviceId);
      }
    }
  });

  platformSos.setMethodCallHandler((call) async {
    if (call.method == "openSosScreen") {
      final args = Map<String, dynamic>.from(call.arguments as Map);
      navigatorKey.currentState?.pushNamed('/sos-alert', arguments: args);
    }
  });
}

class NeuraApp extends StatelessWidget {
  final bool isLoggedIn;
  final String userTier;
  final bool needsOnboarding;
  final bool needssosContact;
  final bool needsWakeword;

  const NeuraApp({
    required this.isLoggedIn,
    required this.userTier,
    required this.needsOnboarding,
    required this.needssosContact,
    required this.needsWakeword,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Neura Mitram',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: ThemeMode.system,
      navigatorKey: navigatorKey,
      home: SplashRedirector(
        isLoggedIn: isLoggedIn,
        needsOnboarding: needsOnboarding,
        needssosContact: needssosContact,
        needsWakeword: needsWakeword,
      ),
      onGenerateRoute: (settings) {
        if (settings.name == '/sos-alert') {
          final args = settings.arguments as Map<String, dynamic>? ?? {};
          return MaterialPageRoute(
            builder: (context) => SosAlertScreen(
              message: args['message'] ?? 'No message',
              location: args['location'] ?? 'Unknown',
              autoSms: args['autoSms'] ?? false,
              backgroundMic: args['backgroundMic'] ?? false,
              proofLog: args['proofLog'] ?? false,
            ),
          );
        }

        return MaterialPageRoute(
          builder: (_) =>
              const Scaffold(body: Center(child: Text("404 – Page not found"))),
        );
      },
      routes: {
        '/login': (context) => const LoginScreen(),
        '/chat': (context) => const ChatLoader(),
        '/upgrade': (context) => const UpgradeScreen(),
        '/onboarding': (context) => const OnboardingScreen(),
        '/profile': (context) => const ProfileScreen(),
        '/manage-plan': (context) => const ManageSubscriptionScreen(),
        '/insights': (context) => const InsightsScreen(),
        '/report-unsafe': (context) => const ReportUnsafeAreaScreen(),
        '/my-reports': (context) => const MyUnsafeReportsScreen(),
        '/sos-contact': (context) => const SosContactScreen(),
        '/nearby-sos': (context) => const NearbySosScreen(),
        '/community-reports': (context) => const CommunityReportsScreen(),
        '/wakeword': (context) => const WakewordTrainerScreen(),
        '/memory': (context) => const MemoryScreen(),
      },
    );
  }
}

class ChatLoader extends StatelessWidget {
  const ChatLoader({super.key});

  Future<String?> _getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('device_id');
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return FutureBuilder<String?>(
      future: _getDeviceId(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const NeuraLoader(message: "Neura is waking up...");
        } else if (snapshot.hasData && snapshot.data != null) {
          return ChatScreen(deviceId: snapshot.data!);
        } else {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "Oops... Something went wrong 😕",
                    textAlign: TextAlign.center,
                    style: textTheme.titleLarge?.copyWith(
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "We couldn’t find your device ID.\nPlease login again to continue.",
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.clear();
                      Navigator.pushReplacementNamed(context, '/');
                    },
                    child: const Text("Go to Login"),
                  ),
                ],
              ),
            ),
          );
        }
      },
    );
  }
}

class SplashRedirector extends StatefulWidget {
  final bool isLoggedIn;
  final bool needsOnboarding;
  final bool needssosContact;
  final bool needsWakeword;

  const SplashRedirector({
    super.key,
    required this.isLoggedIn,
    required this.needsOnboarding,
    required this.needssosContact,
    required this.needsWakeword,
  });

  @override
  State<SplashRedirector> createState() => _SplashRedirectorState();
}

class _SplashRedirectorState extends State<SplashRedirector> {
  @override
  void initState() {
    super.initState();
    try {
      debugPrint("🧠 OnboardingScreen init...");
      _decideRoute();
    } catch (e, st) {
      debugPrint("❌ Onboarding init crash: $e\n$st");
    }
  }

  Future<void> _decideRoute() async {
    await Future.delayed(const Duration(milliseconds: 1500));

    String? nextRoute;

    try {
      if (!widget.isLoggedIn) {
        // 🔹 No device ID yet → Show login screen
        nextRoute = '/login';
      } else if (widget.needsOnboarding) {
        // 🔹 Logged in, but onboarding not completed
        nextRoute = '/onboarding';
      } else if (widget.needssosContact) {
        // 🔹 Onboarding done, but no SOS contact set
        nextRoute = '/sos-contact';
      } else if (widget.needsWakeword) {
        // 🔹 SOS done, but no wakeword set
        nextRoute = '/wakeword';
      } else {
        // ✅ Everything set → Go to chat
        nextRoute = '/chat';
      }

      debugPrint("🚀 Navigating to $nextRoute");

      // ✅ Only navigate if the widget is still in the tree
      if (mounted) {
        Navigator.pushReplacementNamed(context, nextRoute);
      }
    } catch (e) {
      debugPrint("❌ Navigation failed to $nextRoute: $e");

      // 🛑 Show at least a fallback screen
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const Scaffold(
            body: Center(
              child: Text("⚠️ Failed to navigate — please reinstall."),
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const NeuraLoader(message: "Neura is getting ready...");
    //   return const Scaffold(
    //     backgroundColor: Colors.white,
    //     body: Center(child: CircularProgressIndicator()),
    //   );
  }
}
