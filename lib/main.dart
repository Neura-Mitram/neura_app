import 'dart:async';
import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
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
import 'widgets/neura_loader.dart';
import 'services/ws_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final platform = MethodChannel('neura/wakeword');
final platformMic = MethodChannel('com.neura/mic_control');
final platformSos = MethodChannel('sos.screen.trigger');
String? globalDeviceId;
String? globalUserTier; // Added global tier storage
DateTime? lastSosCall;

// Top-level function for isolate
void _startStreamingIsolate(String deviceId) {
  WsService().startStreaming(deviceId);
}

void restartApp(BuildContext context) {
  Navigator.pushAndRemoveUntil(
    context,
    MaterialPageRoute(builder: (context) => const NeuraApp()),
    (route) => false,
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NeuraApp());
}

class NeuraApp extends StatefulWidget {
  const NeuraApp({super.key});

  @override
  State<NeuraApp> createState() => _NeuraAppState();
}

class _NeuraAppState extends State<NeuraApp> {

  Future<Map<String, dynamic>> _loadInitialConfig() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Load all required onboarding flags and user tier
    final deviceId = prefs.getString('device_id');
    final tier = prefs.getString('tier') ?? "free"; // Restored tier
    final onboardingCompleted = prefs.getBool('onboarding_completed') ?? false;
    final sosContactCompleted = prefs.getBool('sos_contacts_completed') ?? false;
    final wakewordCompleted = prefs.getBool('wakeword_completed') ?? false;

    globalDeviceId = deviceId;
    globalUserTier = tier; // Set global tier
    
    return {
      'isLoggedIn': deviceId != null && deviceId.isNotEmpty,
      'userTier': tier, // Return tier in config
      'needsOnboarding': !onboardingCompleted,
      'needssosContact': !sosContactCompleted,
      'needsWakeword': !wakewordCompleted,
    };
  }

  @override
  void dispose() {
    // Clean up platform handlers
    platformMic.setMethodCallHandler(null);
    platformSos.setMethodCallHandler(null);
    super.dispose();
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
          }
          
          if (snapshot.hasError) {
            return Scaffold(
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error, size: 48, color: Colors.red),
                    const SizedBox(height: 16),
                    const Text("Configuration Error", style: TextStyle(fontSize: 18)),
                    const SizedBox(height: 8),
                    Text(snapshot.error.toString(), textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () => restartApp(context),
                      child: const Text("Restart App"),
                    ),
                  ],
                ),
              ),
            );
          }

          final config = snapshot.data!;
          
          
          return SplashRedirector(
            isLoggedIn: config['isLoggedIn'] as bool,
            userTier: config['userTier'] as String, // Pass tier to redirector
            needsOnboarding: config['needsOnboarding'] as bool,
            needssosContact: config['needssosContact'] as bool,
            needsWakeword: config['needsWakeword'] as bool,
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
  final String userTier; // Added tier parameter
  final bool needsOnboarding;
  final bool needssosContact;
  final bool needsWakeword;

  const SplashRedirector({
    super.key,
    required this.isLoggedIn,
    required this.userTier, // Added tier
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
    // Route immediately without delay
    WidgetsBinding.instance.addPostFrameCallback((_) => _decideRoute());
  }

  void _decideRoute() {
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

class ChatLoader extends StatefulWidget {
  const ChatLoader({super.key});

  @override
  State<ChatLoader> createState() => _ChatLoaderState();
}

class _ChatLoaderState extends State<ChatLoader> {
  bool _isLoading = true;
  bool handlersInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeApp();
    _setupPlatformHandlers();
  }

  void _setupPlatformHandlers() {
    if (handlersInitialized) return;
    handlersInitialized = true;

    // Stop overlay service
    platform.invokeMethod('stopOverlayDotService').catchError((e) {
      debugPrint("Overlay service error: $e");
    });

    // Mic handler
    platformMic.setMethodCallHandler((call) async {
      if (call.method == "startMic" && globalDeviceId != null) {
        debugPrint("Mic trigger received - starting isolate");
        Isolate.spawn(_startStreamingIsolate, globalDeviceId!);
      }
      return null;
    });

    // SOS handler
    platformSos.setMethodCallHandler((call) async {
      if (call.method == "openSosScreen") {
        final now = DateTime.now();
        if (lastSosCall != null && 
            now.difference(lastSosCall!) < const Duration(seconds: 5)) {
          return;
        }
        lastSosCall = now;

        final args = call.arguments is Map 
            ? Map<String, dynamic>.from(call.arguments as Map) 
            : {};
        
        if (navigatorKey.currentState != null) {
          navigatorKey.currentState?.pushNamed('/sos-alert', arguments: args);
        }
      }
      return null;
    });
  }

  Future<void> _initializeApp() async {
  bool firebaseFailed = false;

  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint("🔥 Firebase init failed: $e");
    firebaseFailed = true;
  }

  try {
    await SharedPreferences.getInstance();
  } catch (e) {
    debugPrint("⚠️ SharedPreferences init error: $e");
  }

  if (!mounted) return;

  if (firebaseFailed) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('⚠️ Firebase services unavailable. Some features may not work.'),
        backgroundColor: Colors.redAccent,
        duration: Duration(seconds: 3),
      ),
    );
    }

    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const NeuraLoader(message: "Waking Neura...");
    }

    if (globalDeviceId == null || globalDeviceId!.isEmpty) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Oops... Something went wrong 😕"),
              const SizedBox(height: 8),
              const Text("We couldn't find your device ID.\nPlease login again."),
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

    return ChatScreen(
      deviceId: globalDeviceId!,
      userTier: globalUserTier ?? "free",
    );
  }
}
