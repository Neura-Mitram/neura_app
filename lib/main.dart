import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'theme.dart';
import 'screens/chat_screen.dart';
import 'screens/login_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/sos_contact_screen.dart';
import 'screens/wakeword_trainer_screen.dart';
import 'screens/upgrade_screen.dart';
import 'screens/insights_screen.dart';
import 'screens/manage_subscription_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/report_unsafe_area_screen.dart';
import 'screens/my_unsafe_reports_screen.dart';
import 'screens/nearby_sos_screen.dart';
import 'screens/community_reports_screen.dart';
import 'screens/memory_screen.dart';
import 'screens/sos_alert_screen.dart';
import 'utils/restart_utils.dart';
import 'widgets/neura_loader.dart';
import 'services/ws_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final platform = MethodChannel('neura/wakeword');
final platformMic = MethodChannel('com.neura/mic_control');
final platformSos = MethodChannel('sos.screen.trigger');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RestartWidget(child: NeuraApp()));
}

class NeuraApp extends StatelessWidget {
  const NeuraApp({super.key});

  Future<Map<String, dynamic>> _loadInitialConfig() async {
    final prefs = await SharedPreferences.getInstance();

    final deviceId = prefs.getString('device_id');
    final tier = prefs.getString('tier') ?? "free";
    final onboardingCompleted = prefs.getBool('onboarding_completed') ?? false;
    final sosContactCompleted = prefs.getBool('sos_contacts_completed') ?? false;
    final wakewordCompleted = prefs.getBool('wakeword_completed') ?? false;

    platformMic.setMethodCallHandler((call) async {
      if (call.method == "startMic") {
        final id = prefs.getString('device_id');
        if (id != null) {
          debugPrint("🎙️ Mic trigger received — launching WsService stream...");
          await WsService().startStreaming(id);
        }
      }
    });

    platformSos.setMethodCallHandler((call) async {
      if (call.method == "openSosScreen") {
        final args = call.arguments;
        if (args is Map) {
          navigatorKey.currentState?.pushNamed('/sos-alert',
              arguments: Map<String, dynamic>.from(args));
        }
      }
    });

    await platform.invokeMethod('stopOverlayDotService');

    return {
      'isLoggedIn': deviceId != null && deviceId.isNotEmpty,
      'userTier': tier,
      'needsOnboarding': !onboardingCompleted,
      'needssosContact': !sosContactCompleted,
      'needsWakeword': !wakewordCompleted,
    };
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Neura Mitram',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: ThemeMode.system,
      navigatorKey: navigatorKey,
      home: FutureBuilder<Map<String, dynamic>>(
        future: _loadInitialConfig(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const NeuraLoader(message: "Neura is getting ready...");
          } else if (snapshot.hasError) {
            return const Scaffold(body: Center(child: Text("⚠️ Failed to load config")));
          }

          final config = snapshot.data!;
          return SplashRedirector(
            isLoggedIn: config['isLoggedIn'],
            needsOnboarding: config['needsOnboarding'],
            needssosContact: config['needssosContact'],
            needsWakeword: config['needsWakeword'],
          );
        },
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
    _decideRoute();
  }

  Future<void> _decideRoute() async {
    await Future.delayed(const Duration(milliseconds: 1500));

    String route;
    if (!widget.isLoggedIn) {
      route = '/login';
    } else if (widget.needsOnboarding) {
      route = '/onboarding';
    } else if (widget.needssosContact) {
      route = '/sos-contact';
    } else if (widget.needsWakeword) {
      route = '/wakeword';
    } else {
      route = '/chat';
    }

    if (mounted) {
      Navigator.pushReplacementNamed(context, route);
    }
  }

  @override
  Widget build(BuildContext context) {
    return const NeuraLoader(message: "Neura is waking up...");
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
                  const Text("Oops... Something went wrong 😕"),
                  const SizedBox(height: 8),
                  const Text("We couldn’t find your device ID.\nPlease login again."),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.clear();
                      if (!context.mounted) return;
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