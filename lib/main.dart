import 'package:flutter/material.dart';
import 'package:neura_app/screens/insights_screen.dart';
import 'package:neura_app/screens/manage_plan_screen.dart';
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
import 'screens/WakewordTrainerScreen.dart';
import 'services/translation_service.dart';
import 'utils/restart_utils.dart';
import 'package:flutter/services.dart';
import '../services/ws_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

final platform = MethodChannel('neura/wakeword');
final platformMic = MethodChannel('com.neura/mic_control');
final platformSos = MethodChannel('sos.screen.trigger');

Future<void> startWakewordService() async {
  try {
    await platform.invokeMethod('startWakewordService');
  } catch (e) {
    debugPrint("🚨 Error starting WakewordService: $e");
  }
}

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
  // await prefs.clear();

  // ✅ Restore cached translations for tr() to work from first screen
  await TranslationService.restoreCachedTranslations();

  final deviceId = prefs.getInt('device_id');
  final tier = prefs.getString('tier') ?? "free"; // fixed key
  final onboardingCompleted = prefs.getBool('onboarding_completed') ?? false;
  final sosContactCompleted = prefs.getBool('sos_contacts_completed') ?? false;
  final wakewordCompleted = prefs.getBool('wakeword_completed') ?? false;
  final activeMode = prefs.getString('active_mode') ?? "manual"; // ✅

  bool isLoggedIn = deviceId != null;
  bool needsOnboarding = !onboardingCompleted;
  bool needssosContact = !sosContactCompleted;
  bool needsWakeword = !wakewordCompleted;

  // ✅ Automatically start wakeword background listener
  if (deviceId != null && wakewordCompleted && activeMode == "ambient") {
    await startWakewordService();
    await stopOverlayDotService();
  }

  // ✅ Automatically Start Mic
  platformMic.setMethodCallHandler((call) async {
    if (call.method == "startMic") {
      final prefs = await SharedPreferences.getInstance();
      final deviceId = prefs.getInt('device_id');
      if (deviceId != null) {
        debugPrint("🎙️ Mic trigger received — launching WsService stream...");
        await WsService().startStreaming(deviceId.toString());
      }
    }
  });

  // ✅ Automatically Open SOS Channel
  platformSos.setMethodCallHandler((call) async {
    if (call.method == "openSosScreen") {
      final args = Map<String, dynamic>.from(call.arguments as Map);
      navigatorKey.currentState?.pushNamed('/sos-alert', arguments: args);
    }
  });

  runApp(
    RestartWidget(
      // ✅ Wrap app
      child: NeuraApp(
        isLoggedIn: isLoggedIn,
        userTier: tier,
        needsOnboarding: needsOnboarding,
        needssosContact: needssosContact,
        needsWakeword: needsWakeword,
      ),
    ),
  );
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
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    String initialRoute;

    if (!isLoggedIn) {
      initialRoute = '/';
    } else if (needsOnboarding) {
      initialRoute = '/onboarding';
    } else if (needssosContact) {
      initialRoute = '/sos-contact';
    } else if (needsWakeword) {
      initialRoute = '/wakeword';
    } else {
      initialRoute = '/chat';
    }

    return MaterialApp(
      title: 'Neura ManoMitram',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: ThemeMode.system,
      navigatorKey: navigatorKey,
      initialRoute: initialRoute,
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
        // Add fallback or other routes here
        return MaterialPageRoute(
          builder: (_) =>
              const Scaffold(body: Center(child: Text("404 – Page not found"))),
        );
      },
      routes: {
        '/': (context) => const LoginScreen(),
        '/chat': (context) => const ChatLoader(),
        '/upgrade': (context) => const UpgradeScreen(),
        '/onboarding': (context) => const OnboardingScreen(),
        '/profile': (context) => const ProfileScreen(),
        '/manage-plan': (context) => const ManagePlanScreen(),
        '/insights': (context) => const InsightsScreen(),
        '/report-unsafe': (context) => const ReportUnsafeAreaScreen(),
        '/my-reports': (context) => const MyUnsafeReportsScreen(),
        '/sos-contact': (context) => const SosContactScreen(),
        '/nearby-sos': (context) => const NearbySosScreen(),
        '/community-reports': (context) => const CommunityReportsScreen(),
        '/wakeword': (context) => const WakewordTrainerScreen(),
      },
    );
  }
}

class ChatLoader extends StatelessWidget {
  const ChatLoader({super.key});

  Future<int?> _getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('device_id');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int?>(
      future: _getDeviceId(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // ✅ Animated waveform loader here
          return const NeuraLoader(message: "Neura is waking up...");
        } else if (snapshot.hasData && snapshot.data != null) {
          return ChatScreen(deviceId: snapshot.data!.toString());
        } else {
          // ✅ Fallback: Show error and retry or redirect
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Oops... Something went wrong 😕",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2F67B5),
                    ),
                  ),
                  SizedBox(height: 8),
                  const Text(
                    "We couldn’t find your device ID.\nPlease login again to continue.",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.black87),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFF2F67B5),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      textStyle: const TextStyle(fontSize: 16),
                    ),
                    onPressed: () {
                      SharedPreferences.getInstance().then((prefs) {
                        prefs.clear();
                        Navigator.pushReplacementNamed(context, '/');
                      });
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
