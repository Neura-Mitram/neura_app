import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_message.dart';
import '../services/ws_service.dart';
import '../services/chat_api.dart';
import '../services/api_base.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ChatController extends ChangeNotifier {
  final String deviceId;
  String activeMode = "manual"; // default value
  final WsService wsService = WsService();

  // Chat messages
  final List<ChatMessage> messages = [];

  // State flags
  bool isTyping = false;
  bool isSpeaking = false;
  bool isRecording = false;
  String? currentlyPlayingUrl;
  // Recording duration
  int recordingSeconds = 0;
  // AI personalization
  String aiName = "Neura";
  String voice = "male";
  String userTier = "free";

  String? detectedSummaryType;
  Map<String, dynamic>? summaryData;

  final Queue<ChatMessage> _nudgeQueue = Queue();
  bool _isPlayingNudge = false;
  bool muteNudges = false;

  // Audio player
  final player = AudioPlayer();

  ChatController({required this.deviceId});

  Future<void> startAmbientIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final deviceId = prefs.getString('device_id');
    final mode = prefs.getString('active_mode');

    if (mode == "ambient" && deviceId != null) {
      await _playWakeWordDetect();
      await wsService.startStreaming(deviceId.toString());
    }
  }

  /// Play WakeWord Detect Intro
  Future<void> _playWakeWordDetect() async {
    try {
      final player = AudioPlayer();
      await player.setVolume(1.0);
      await player.setAsset('assets/audio/wakeworddetect_neura.mp3');
      await player.play();
    } catch (e) {
      print("❌ Playback error: $e");
    }
  }

  /// Load preferences like voice & AI name
  Future<void> loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    aiName = prefs.getString('ai_name') ?? "Neura";
    voice = prefs.getString('voice') ?? "male";
    activeMode = prefs.getString('active_mode') ?? "manual"; // 👈 Add this line
    userTier = prefs.getString('tier') ?? "free";
    notifyListeners();
  }

  bool get isPro => userTier == "pro";

  /// Send a text message
  Future<void> sendTextMessage(String text) async {
    if (text.trim().isEmpty) return;

    final now = DateTime.now();
    final userMessage = ChatMessage(
      text: text,
      isUser: true,
      timestamp: now,
      isPending: true,
    );
    messages.add(userMessage);
    isTyping = true;
    isSpeaking = true;
    notifyListeners();

    try {
      final data = await sendMessageToNeura(text, deviceId);

      // ✅ mark as sent
      userMessage.isPending = false;
      userMessage.isFailed = false;

      final Map<String, String> summaryKeyMap = {
        'goal_summary': 'goal',
        'journal_summary': 'journal',
        'habit_summary': 'habit',
        'mood_summary': 'mood',
        'daily_checkin_summary': 'checkin',
        'fallback_interpretation': 'fallback',
      };

      for (final key in summaryKeyMap.keys) {
        if (data.containsKey(key)) {
          detectedSummaryType = summaryKeyMap[key]; // e.g., 'goal'
          summaryData = data[key];
          break;
        }
      }

      final isPrompt = (data['rawData']?['metadata'] == "in_chat");

      messages.add(
        ChatMessage(
          text: data['reply'],
          isUser: false,
          emotion: data['emotion'],
          messagesUsed: data['messages_used_this_month'],
          messagesRemaining: data['messages_remaining'],
          suggestions: (data['replies'] as List<dynamic>?)?.cast<String>(),
          summaryType: detectedSummaryType,
          summaryData: summaryData,
          isPrompt: isPrompt,
          timestamp: DateTime.now(),
          rawData: data['rawData'],
        ),
      );
      // 🔴 New: Log SOS time + emotion to backend
      await _logSosMetadataIfAny(data);
    } catch (e) {
      // ❌ mark as failed
      userMessage.isPending = false;
      userMessage.isFailed = true;

      messages.add(
        ChatMessage(
          text: "❌ Error: $e",
          isUser: false,
          timestamp: DateTime.now(),
        ),
      );
    } finally {
      isTyping = false;
      isSpeaking = false;
      notifyListeners();
    }
  }

  /// Reset everything (e.g., on logout)
  void clear() {
    messages.clear();
    isTyping = false;
    isRecording = false;
    isSpeaking = false;
    recordingSeconds = 0;
    notifyListeners();
  }

  /// Optional: listen for playback completion
  void setupPlayerListener(VoidCallback onComplete) {
    player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        currentlyPlayingUrl = null;
        _isPlayingNudge = false;
        _playNextNudge(); // ▶️ play next one in queue
        notifyListeners();
        onComplete();
      }
    });
  }

  void enqueueNudge(ChatMessage msg) {
    _nudgeQueue.add(msg);
    if (!_isPlayingNudge) {
      _playNextNudge();
    }
  }

  void _playNextNudge() async {
    if (_nudgeQueue.isEmpty || _isPlayingNudge) return;

    final msg = _nudgeQueue.removeFirst();
    if (msg.voiceUrl != null) {
      try {
        _isPlayingNudge = true;
        currentlyPlayingUrl = msg.voiceUrl;
        await player.setUrl(msg.voiceUrl!);
        await player.play();
      } catch (e) {
        _isPlayingNudge = false;
        _playNextNudge(); // skip if error
      }
    }
  }

  void toggleNudgeMute() {
    muteNudges = !muteNudges;
    notifyListeners();
  }

  void setRecording(bool value) {
    isRecording = value;
    notifyListeners();
  }

  Future<void> _logSosMetadataIfAny(Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      final deviceId = prefs.getInt('device_id');

      if (token == null || deviceId == null) return;

      final rawData = data['rawData'];
      if (rawData == null || rawData['trigger_sos_force'] != true) return;

      final uri = Uri.parse('$Baseurl/safety/log-sos-alert');
      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          "device_id": deviceId,
          "message": rawData['sos_message'] ?? "Triggered via auto voice alert",
          "emotion": data['emotion'] ?? "unknown",
          "timestamp": DateTime.now().toIso8601String(),
        }),
      );

      if (response.statusCode != 200) {
        debugPrint("⚠️ SOS metadata not logged: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("❌ Error logging SOS metadata: $e");
    }
  }

  void addSummaryCard({
    required String type,
    required String emoji,
    required String text,
    required DateTime timestamp,
  }) {
    final summaryMessage = ChatMessage(
      isUser: false,
      summaryType: type,
      summaryData: {
        'emoji': emoji,
        'text': text,
        'timestamp': timestamp.toIso8601String(),
      },
      timestamp: timestamp,
    );

    // ⛔ Cap list at 20 messages to avoid unbounded memory
    if (messages.length >= 20) {
      messages.removeAt(0); // remove oldest
    }

    messages.add(summaryMessage);
    notifyListeners();
  }

  /// Dispose audio resources
  void disposeAudio() {
    player.dispose();
    currentlyPlayingUrl = null;
  }

  void updateActiveMode(String mode) {
    activeMode = mode;
    notifyListeners();
  }

  void markVoicePlaybackDone() {
    currentlyPlayingUrl = null;
    notifyListeners();
  }

  /// Whether there is an ongoing upload
  bool get hasActiveVoiceUpload =>
      messages.any((m) => m.isVoice && m.voiceUrl == null);
}
