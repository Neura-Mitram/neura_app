import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import '../widgets/animated_waveform_bars.dart';
import '../widgets/neura_loader.dart';
import '../services/auth_service.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:lottie/lottie.dart';
import 'package:vibration/vibration.dart';
import '../services/translation_service.dart';
import 'package:flutter/services.dart';
import '../widgets/setup_progress_stepper.dart';

class WakewordTrainerScreen extends StatefulWidget {
  const WakewordTrainerScreen({super.key});

  @override
  State<WakewordTrainerScreen> createState() => _WakewordTrainerScreenState();
}

class _WakewordTrainerScreenState extends State<WakewordTrainerScreen> {
  final List<File> recordedSamples = [];
  int currentStep = 0;
  bool isUploading = false;
  bool isRecording = false;
  FlutterSoundRecorder? _recorder;
  final platform = MethodChannel('neura/wakeword');
  final platformNudge = MethodChannel('neura/native/nudge');

  @override
  void initState() {
    super.initState();
    _recorder = FlutterSoundRecorder();
    _initializeRecorder();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      TranslationService.loadScreenOnInit(context, "wakeword", onDone: () {
        setState(() {});
      });
    });
  }

  Future<void> _initializeRecorder() async {
    await _recorder!.openRecorder();
    await Permission.microphone.request();
  }

  Future<void> _recordSample() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/sample$currentStep.aac';

    setState(() {
      isRecording = true;
    });

    await _recorder!.startRecorder(toFile: path);
    await Future.delayed(const Duration(seconds: 2));
    await _recorder!.stopRecorder();

    recordedSamples.add(File(path));
    setState(() {
      currentStep++;
      isRecording = false;
    });
  }

  Future<void> _submitSamples() async {
    setState(() => isUploading = true);
    final prefs = await SharedPreferences.getInstance();
    final deviceId = prefs.getString('device_id');

    try {
      if (deviceId == null) throw Exception("Missing device ID");

      final backendModelPath = await AuthService().uploadWakewordSamples(
        deviceId: deviceId,
        audioSamples: recordedSamples,
      );
      debugPrint("Backend model path: $backendModelPath");

      final localModelPath = await AuthService().downloadWakewordModel(deviceId);
      if (localModelPath != null) {
        await prefs.setString('wakeword_model_path', localModelPath);
      }

      await prefs.setBool('wakeword_completed', true);
      await prefs.setBool('playon_Completed_Setup', false);
      await prefs.setString('active_mode', "ambient");

      if (context.mounted) {
        final theme = Theme.of(context);
        await showDialog(
          context: context,
          builder: (ctx) => Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Container(
              decoration: BoxDecoration(
                color: theme.dialogBackgroundColor,
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Lottie.asset('assets/neura_success_check.json', height: 120, repeat: false),
                  const SizedBox(height: 20),
                  Text(
                    TranslationService.tr("Wakeword Trained!"),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    TranslationService.tr("Your assistant can now recognize your voice 🧠"),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      foregroundColor: theme.colorScheme.onPrimary,
                      backgroundColor: theme.colorScheme.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.pushReplacementNamed(context, '/chat');
                      startWakewordService();
                    },
                    child: Text(TranslationService.tr("Continue")),
                  ),
                ],
              ),
            ),
          ),
        );
        if (await Vibration.hasVibrator()) {
          Vibration.vibrate(duration: 50);
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.tr("Upload failed: {error}").replaceFirst("{error}", "$e"),
            ),
          ),
        );
      }
    } finally {
      setState(() => isUploading = false);
    }
  }

  Future<void> startWakewordService() async {
    try {
      await platform.invokeMethod('startWakewordService');
      final prefs = await SharedPreferences.getInstance();
      final lang = prefs.getString('preferred_lang') ?? 'en';
      await sendNudgeToNative("🚀", "Wakeword trained!", lang);
    } catch (e) {
      debugPrint("🚨 Error starting WakewordService: $e");
    }
  }

  Future<void> sendNudgeToNative(String emoji, String text, String lang) async {
    try {
      await platformNudge.invokeMethod('showNudgeBubble', {
        'emoji': emoji,
        'text': text,
        'lang': lang,
      });
    } catch (e) {
      print('Failed to show native nudge: $e');
    }
  }

  @override
  void dispose() {
    _recorder?.closeRecorder();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(TranslationService.tr("Train Wakeword")),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SetupProgressStepper(currentStep: SetupStep.wakeword),
                    const SizedBox(height: 20),
                    if (isUploading)
                      NeuraLoader(
                        message: TranslationService.tr("Uploading your voice samples..."),
                      )
                    else ...[
                      const SizedBox(height: 24),
                      Text(
                        TranslationService.tr("Say your assistant's name (${3 - currentStep} left)"),
                        style: theme.textTheme.titleMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      AnimatedWaveformBars(isRecording: isRecording),
                      const SizedBox(height: 40),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.mic),
                        onPressed: isRecording || currentStep >= 3 ? null : _recordSample,
                        label: Text(
                          isRecording
                              ? TranslationService.tr("Recording...")
                              : TranslationService.tr("Record Sample ${currentStep + 1}"),
                        ),
                      ),
                      const SizedBox(height: 40),
                      if (currentStep == 3)
                        ElevatedButton.icon(
                          icon: const Icon(Icons.upload),
                          onPressed: _submitSamples,
                          label: Text(TranslationService.tr("Upload Samples")),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
