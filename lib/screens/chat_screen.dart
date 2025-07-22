import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neura_app/controllers/chat_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:http/http.dart' as http;
import '../services/api_base.dart';
import '../models/chat_message.dart';
import '../controllers/chat_provider.dart';
import '../widgets/avatar_widget.dart';
import '../widgets/typing_indicator.dart';
import '../widgets/voice_message_bubble.dart';
import '../widgets/tier_usage_bar.dart';
import '../screens/profile_screen.dart';
import '../widgets/animated_waveform_bars.dart';
import '../services/cluster_alert_service.dart';
import '../services/community_alert_banner_service.dart';
import '../services/ws_service.dart';
import '../services/translation_service.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String deviceId;
  const ChatScreen({super.key, required this.deviceId});

  @override
  ConsumerState<ChatScreen> createState() => ChatScreenState();
}

class ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final WsService wsService = WsService();

  Timer? _recordingTimer;
  int _recordingSeconds = 0;

  bool sosLaunched = false;

  @override
  void initState() {
    super.initState();
    ref
        .read(chatControllerProvider(widget.deviceId).notifier)
        .loadPreferences();
    // ✅ Start ambient stream if mode is ambient
    ref
        .read(chatControllerProvider(widget.deviceId).notifier)
        .startAmbientIfNeeded();
    _startClusterPingChecker();
  }

  Future<void> _startRecording() async {
    final prefs = await SharedPreferences.getInstance();
    final deviceId = prefs.getString('device_id');

    if (deviceId != null) {
      await wsService.startStreaming(deviceId);
      setState(() {
        _recordingSeconds = 0;
        ref
            .read(chatControllerProvider(widget.deviceId).notifier)
            .setRecording(true);
      });

      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() => _recordingSeconds++);
        }
      });
    }
  }

  Future<void> _stopRecording() async {
    await wsService.stopStreaming();
    _recordingTimer?.cancel();
    ref
        .read(chatControllerProvider(widget.deviceId).notifier)
        .setRecording(false);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  Widget _buildMessage(
    ChatMessage msg,
    bool showDateHeader,
    ChatController notifier,
  ) {
    final theme = Theme.of(context);
    // final alignment = msg.isUser ? Alignment.centerRight : Alignment.centerLeft;

    if (msg.isVoice) {
      // If upload failed, show retry chip
      // Otherwise, normal bubble
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisAlignment: msg.isUser
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: [
            if (!msg.isUser) ...[
              const CircleAvatar(
                radius: 16,
                backgroundImage: AssetImage('assets/neura_logo.png'),
              ),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  VoiceMessageBubble(
                    audioUrl: msg.voiceUrl ?? "",
                    duration: msg.duration ?? const Duration(seconds: 2),
                    timestamp: msg.timestamp,
                    showDateHeader: showDateHeader,
                    emotion: msg.emotion,
                    onPlaybackComplete: () {
                      notifier.markVoicePlaybackDone();
                    },
                    isHighlighted:
                        msg.isUser &&
                        msg.voiceUrl != null &&
                        notifier.messages.reversed.firstWhere(
                              (m) =>
                                  m.isVoice && m.voiceUrl != null && m.isUser,
                              orElse: () => ChatMessage(isUser: true),
                            ) ==
                            msg,
                  ),

                  // 👇 Status badge below voice bubble
                  if (msg.isUser)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, left: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (msg.isPending == true)
                            Text(
                              TranslationService.tr("Sending..."),
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey,
                              ),
                            ),
                          if (msg.isFailed == true)
                            Text(
                              TranslationService.tr("❌ Failed"),
                              style: TextStyle(fontSize: 10, color: Colors.red),
                            ),
                          if (msg.isPending == false && msg.isFailed != true)
                            Text(
                              TranslationService.tr("Sent ✅"),
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.green,
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (msg.isUser) ...[
              const SizedBox(width: 8),
              const CircleAvatar(
                radius: 16,
                child: Icon(Icons.person, size: 16),
              ),
            ],
          ],
        ),
      );
    } else {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showDateHeader)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(child: Text(_dateHeader(msg.timestamp))),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisAlignment: msg.isUser
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
              children: [
                if (!msg.isUser) ...[
                  const CircleAvatar(
                    radius: 16,
                    backgroundImage: AssetImage('assets/neura_logo.png'),
                  ),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: GestureDetector(
                    onLongPress: () => _showReactionBar(
                      context,
                      msg,
                    ), // 👈 triggers emoji menu
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: msg.isUser
                            ? theme.colorScheme.primary.withOpacity(0.1)
                            : theme.cardColor,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(msg.text ?? ''),
                          if (!msg.isUser && msg.emotion != null)
                            Text(
                              TranslationService.tr(
                                "Emotion: {emotion}",
                              ).replaceAll("{emotion}", msg.emotion!),
                            ),
                          Text(_formatTimestamp(msg.timestamp)),

                          // ✅ Message Status
                          if (msg.isUser)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (msg.isPending == true)
                                    Text(
                                      TranslationService.tr("Sending..."),
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  if (msg.isFailed == true)
                                    Text(
                                      TranslationService.tr("❌ Failed"),
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.red,
                                      ),
                                    ),
                                  if (msg.isPending == false &&
                                      msg.isFailed != true)
                                    Text(
                                      TranslationService.tr("Sent ✅"),
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.green,
                                      ),
                                    ),
                                ],
                              ),
                            ),

                          // ✅ Reaction Emoji
                          if (msg.reaction != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                msg.reaction!,
                                style: const TextStyle(fontSize: 18),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),

                if (msg.isUser) ...[
                  const SizedBox(width: 8),
                  const CircleAvatar(
                    radius: 16,
                    child: Icon(Icons.person, size: 16),
                  ),
                ],
              ],
            ),
          ),
          if (!msg.isUser &&
              msg.suggestions != null &&
              msg.suggestions!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 12, right: 12, top: 6),
              child: Wrap(
                spacing: 8,
                children: msg.suggestions!.map((s) {
                  return ActionChip(
                    label: Text(s),
                    onPressed: () {
                      notifier.sendTextMessage(s);
                      _scrollToBottom();
                    },
                  );
                }).toList(),
              ),
            ),
        ],
      );
    }
  }

  void _showReactionBar(BuildContext context, ChatMessage msg) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          margin: const EdgeInsets.all(40),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: ['❤️', '😂', '👍', '😮', '🔥', '👎'].map((emoji) {
              return GestureDetector(
                onTap: () => Navigator.of(ctx).pop(emoji),
                child: Text(emoji, style: const TextStyle(fontSize: 24)),
              );
            }).toList(),
          ),
        );
      },
    );

    if (selected != null) {
      setState(() {
        msg.reaction = selected;
      });
    }
  }

  String _formatTimestamp(DateTime dt) {
    return "${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
  }

  void showSosAlertDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(TranslationService.tr("Emergency Alert")),
        content: Text(
          TranslationService.tr(
            "Neura detected a dangerous keyword. Do you want to send an SOS alert now?",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(TranslationService.tr("Cancel")),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.pushNamed(context, '/sos-alert');
            },
            icon: const Icon(Icons.warning),
            label: Text(TranslationService.tr("Send SOS")),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade800,
            ),
          ),
        ],
      ),
    );
  }

  void _startClusterPingChecker() {
    Timer.periodic(const Duration(minutes: 3), (_) {
      ClusterAlertService.checkForNearbyUnsafePings();
    });
  }

  String _dateHeader(DateTime dt) {
    final now = DateTime.now();
    if (DateUtils.isSameDay(dt, now)) return 'Today';
    return "${dt.day}/${dt.month}/${dt.year}";
  }

  bool _isSameDay(DateTime? a, DateTime? b) {
    if (a == null || b == null) return false;
    return DateUtils.isSameDay(a, b);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    ModalRoute.of(context)?.addScopedWillPopCallback(() async {
      sosLaunched = false;
      return true;
    });
  }

  Future<void> callInterpreter(ChatController chat) async {
    final isCurrentlyOn = chat.activeMode == "interpreter";

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString("auth_token") ?? "";

    final response = await http.post(
      Uri.parse("$Baseurl/voice/toggle-interpreter-mode"),
      headers: {"Authorization": "Bearer $token"},
      body: {
        "device_id": widget.deviceId,
        "enable": (!isCurrentlyOn).toString(),
      },
    );

    if (response.statusCode == 200) {
      final result = jsonDecode(response.body);
      final message = result["message"] ?? "Updated.";
      final newMode = result["active_mode"] ?? "manual";

      // ✅ Update local controller state
      chat.updateActiveMode(newMode);

      // ✅ Optionally persist
      await prefs.setString("active_mode", newMode);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Failed to toggle Interpreter Mode.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatControllerProvider(widget.deviceId));
    final notifier = ref.read(chatControllerProvider(widget.deviceId).notifier);

    ref.listen<ChatController>(chatControllerProvider(widget.deviceId), (
      previous,
      next,
    ) {
      if (sosLaunched) return; // prevent re-entry

      if (previous?.messages.length != next.messages.length) {
        _scrollToBottom();

        final last = next.messages.last;
        final raw = last.rawData;

        if (raw?['trigger_sos_force'] == true) {
          sosLaunched = true;
          Navigator.pushNamed(context, '/sos-alert');
        } else if (raw?['trigger_sos'] == true) {
          sosLaunched = true;
          showSosAlertDialog(context);
        }
      }
    });

    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          "${chat.aiName} ${TranslationService.tr("Smart Assistant")}",
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              notifier.disposeAudio();
              if (mounted) Navigator.pushReplacementNamed(context, '/');
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              const CommunityAlertBanner(),
              const SizedBox(height: 8),
              AssistantAvatar(
                voice: chat.voice,
                isSpeaking: chat.isSpeaking || chat.isTyping,
              ),
              if (chat.isTyping)
                const Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: TypingIndicator(),
                ),
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  itemCount: chat.messages.length,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemBuilder: (context, index) {
                    final current = chat.messages[index];
                    final previous = index > 0
                        ? chat.messages[index - 1]
                        : null;
                    final showDateHeader =
                        previous == null ||
                        !_isSameDay(current.timestamp, previous.timestamp);
                    return _buildMessage(current, showDateHeader, notifier);
                  },
                ),
              ),
              if (chat.messages.isNotEmpty)
                Builder(
                  builder: (_) {
                    final lastBot = chat.messages.lastWhere(
                      (m) => !m.isUser,
                      orElse: () => ChatMessage(isUser: false),
                    );
                    if (lastBot.messagesUsed != null &&
                        lastBot.messagesRemaining != null) {
                      final used = lastBot.messagesUsed!;
                      final total = used + lastBot.messagesRemaining!;
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        child: TierUsageBar(used: used, total: total),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              // Input field
              Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        decoration: InputDecoration(
                          hintText: TranslationService.tr("Ask me anything..."),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        final text = _controller.text.trim();
                        if (text.isNotEmpty) {
                          notifier.sendTextMessage(text);
                          _controller.clear();
                          // Auto-scroll after sending
                          Future.delayed(const Duration(milliseconds: 500), () {
                            if (mounted) {
                              _scrollController.animateTo(
                                _scrollController.position.maxScrollExtent,
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeOut,
                              );
                            }
                          });
                        }
                      },
                      child: const Icon(Icons.send, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Mic button
          Positioned(
            bottom: 90,
            left: MediaQuery.of(context).size.width / 2 - 40,
            child: GestureDetector(
              onLongPressStart: (_) => _startRecording(),
              onLongPressEnd: (_) => _stopRecording(),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: chat.isRecording ? Colors.red : theme.primaryColor,
                ),
                child: const Icon(Icons.mic, color: Colors.white, size: 30),
              ),
            ),
          ),
          // Recording status
          if (chat.isRecording)
            Positioned(
              bottom: 60,
              left: MediaQuery.of(context).size.width / 2 - 80,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      "${TranslationService.tr("Recording...")} ${_recordingSeconds}s",
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: 100,
                    height: 30,
                    child: AnimatedWaveformBars(isRecording: true),
                  ),
                ],
              ),
            ),
          // Profile button
          Positioned(
            top: 20,
            right: 20,
            child: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ProfileScreen(),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context).primaryColor,
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context).primaryColor.withOpacity(0.4),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(Icons.person, color: Colors.white, size: 24),
              ),
            ),
          ),
          // 🟦 Toggle Interpreter Floating Button
          Positioned(
            bottom: 20,
            right: 20,
            child: FloatingActionButton.extended(
              onPressed: () => callInterpreter(chat),
              icon: Icon(
                chat.activeMode == "interpreter"
                    ? Icons.translate
                    : Icons.translate_outlined,
              ),
              label: Text(
                chat.activeMode == "interpreter"
                    ? "Interpreter ON"
                    : "Interpreter OFF",
              ),
              backgroundColor: chat.activeMode == "interpreter"
                  ? Colors.blueAccent
                  : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}
