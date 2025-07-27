import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class WakewordService {
  static final WakewordService _instance = WakewordService._internal();
  factory WakewordService() => _instance;
  WakewordService._internal();

  FlutterSoundRecorder? _recorder;
  Interpreter? _interpreter;
  bool _isListening = false;
  Timer? _recordingTimer;

  Future<void> init() async {
    _recorder = FlutterSoundRecorder();
    await _recorder!.openRecorder();
    await _loadModel();
  }

  Future<void> _loadModel() async {
    final prefs = await SharedPreferences.getInstance();
    final modelPath = prefs.getString('wakeword_model_path');

    if (modelPath == null || !File(modelPath).existsSync()) {
      debugPrint("Wakeword model not found.");
      return;
    }

    _interpreter = Interpreter.fromFile(File(modelPath));
    debugPrint("Wakeword model loaded ✅");
  }

  Future<void> start() async {
    if (_isListening) return;
    _isListening = true;

    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/wakeword_temp.wav';

    _recordingTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!_isListening) return;

      try {
        await _recorder!.startRecorder(toFile: path, codec: Codec.pcm16WAV);
        await Future.delayed(const Duration(seconds: 1));
        await _recorder!.stopRecorder();

        final audioFile = File(path);
        final result = await _runModel(audioFile);

        if (result == true) {
          debugPrint("👂 Wakeword detected!");
          // TODO: Trigger your wakeword action here
        }
      } catch (e) {
        debugPrint("Wakeword listening error: $e");
      }
    });
  }

  Future<bool> _runModel(File audioFile) async {
    if (_interpreter == null) return false;

    // Simulate input — replace with actual audio preprocessing
    var input = List.generate(1 * 16000, (i) => 0.0).reshape([1, 16000]);
    var output = List.filled(1, 0.0).reshape([1, 1]);

    _interpreter!.run(input, output);

    return output[0][0] > 0.7; // Adjust threshold as needed
  }

  Future<void> stop() async {
    _isListening = false;
    _recordingTimer?.cancel();
    await _recorder?.stopRecorder();
  }

  bool get isListening => _isListening;
}
