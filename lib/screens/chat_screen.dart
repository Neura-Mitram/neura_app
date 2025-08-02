import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neura_app/controllers/chat_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:vibration/vibration.dart';

import '../services/device_service.dart';
import '../widgets/chat_summary_cards.dart';
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
import '../services/profile_service.dart';
import '../services/chat_api.dart';
import 'package:flutter/services.dart';

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
  bool memoryEnabled = true;

  bool isPrivateMode = false;
  bool privateLoading = true;
  int remainingPrivateMins = 0;
  Timer? privateModeTimer;

  @override
  void initState() {
    super.initState();
    _setupNativeSummaryListener();
    _handleFirstTimeLanding();
    _loadMemoryStatus();
    _fetchPrivateMode();
    _retryFCMTokenIfNeeded();

    ref
        .read(chatControllerProvider(widget.deviceId).notifier)
        .loadPreferences();
    ref
        .read(chatControllerProvider(widget.deviceId).notifier)
        .startAmbientIfNeeded();
    _startClusterPingChecker();

    // ✅ Load translations for preferred language
    WidgetsBinding.instance.addPostFrameCallback((_) {
    TranslationService.loadScreenOnInit(context, "chat", onDone: () {
      setState(() {}); // optional if you want to refresh UI
      });
    });
  }

  void _setupNativeSummaryListener() {
    const MethodChannel summaryChannel = MethodChannel('neura/chat/summary');

    summaryChannel.setMethodCallHandler((call) async {
      if (call.method == 'pushChatSummaries') {
        final raw = call.arguments;
        if (raw != null && raw is String) {
          final List<dynamic> data = jsonDecode(raw);
          final controller = ref.read(
            chatControllerProvider(widget.deviceId).notifier,
          );

          for (final item in data) {
            if (item is Map || item is Map<String, dynamic>) {
              final type = item['type'] ?? 'nudge';
              final emoji = item['emoji'] ?? '';
              final text = item['text'] ?? '';
              final timestamp =
                  item['timestamp'] ?? DateTime.now().millisecondsSinceEpoch;

              controller.addSummaryCard(
                type: type,
                emoji: emoji,
                text: text,
                timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp),
              );
            }
          }
        }
      }
    });
  }

  void _handleFirstTimeLanding() async {
    final prefs = await SharedPreferences.getInstance();
    final hasPlayed = prefs.getBool('playon_Completed_Setup') ?? false;

    if (hasPlayed) return; // ✅ already played once

    final lang = prefs.getString('preferred_lang') ?? 'en';
    final voice = prefs.getString('voice') ?? 'female';
    final aiName = prefs.getString('ai_name') ?? 'Neura';
    final voiceId = voice == 'male'
        ? 'EXAVITQu4vr4xnSDxMaL'
        : 'onwK4e9ZLuTAKqWW03F9';
    final welcomeText = TranslationService.tr(
      "Neura’s activated. I’m $aiName, with you, always.",
    );

    // ✅ Show Snackbar
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(welcomeText),
        duration: const Duration(seconds: 3),
      ),
    );

    // ✅ Play Welcome Voice
    try {
      await wsService.playStremOnce(welcomeText, voiceId, lang);
    } catch (e) {
      debugPrint("🎧 Playback error: $e");
    }

    await prefs.setBool('playon_Completed_Setup', true); // ✅ set it after play
  }

  Future<void> _fetchPrivateMode() async {
    try {
      final status = await getPrivateModeStatus(widget.deviceId);
      if (mounted) {
        setState(() {
          isPrivateMode = status['is_private'] as bool;
          remainingPrivateMins = status['time_remaining'] as int? ?? 0;
          privateLoading = false;
        });
        if (isPrivateMode && remainingPrivateMins > 0) {
          _startPrivateModeTimer();
        }
      }
    } catch (_) {
      if (mounted) setState(() => privateLoading = false);
    }
  }

  void _startPrivateModeTimer() {
    privateModeTimer?.cancel();
    privateModeTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (remainingPrivateMins > 0) {
        setState(() => remainingPrivateMins--);
      } else {
        timer.cancel();
        setState(() => isPrivateMode = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(TranslationService.tr("Private mode expired")),
          ),
        );
      }
    });
  }

  Future<void> _togglePrivateMode() async {
    try {
      final updated = await togglePrivateMode(widget.deviceId, !isPrivateMode);
      if (mounted) {
        setState(() {
          isPrivateMode = updated;
          remainingPrivateMins = updated ? 30 : 0;
        });
        if (await Vibration.hasVibrator()) {
          Vibration.vibrate(duration: 80);
        }
        if (updated) _startPrivateModeTimer();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              updated
                  ? TranslationService.tr("Private mode enabled.")
                  : TranslationService.tr("Private mode disabled."),
            ),
          ),
        );
      }
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            TranslationService.tr("Failed to update Private Mode."),
          ),
        ),
      );
    }
  }

  Future<void> _loadMemoryStatus() async {
    final status = await getCurrentMemoryStatus();
    if (mounted) {
      setState(() => memoryEnabled = status);
    }
  }

  Future<void> _toggleMemory(bool value) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          value
              ? TranslationService.tr("Enable Memory?")
              : TranslationService.tr("Disable Memory?"),
        ),
        content: Text(
          value
              ? TranslationService.tr(
                  "Memory is now ON. Neura will start remembering your conversations to help you better.",
                )
              : TranslationService.tr(
                  "Memory is now OFF. Neura will not remember anything from your conversations moving forward.",
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(TranslationService.tr("Cancel")),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(TranslationService.tr("OK")),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final updated = await toggleMemory(enabled: value);
      if (updated) {
        setState(() => memoryEnabled = value);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              value
                  ? TranslationService.tr("Memory enabled.")
                  : TranslationService.tr("Memory disabled."),
            ),
          ),
        );
      }
    }
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

    // 🎙️ Voice Message
    if (msg.isVoice) {
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
                backgroundImage: AssetImage('assets/splash/neura_logo.png'),
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
                    onPlaybackComplete: () => notifier.markVoicePlaybackDone(),
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
                  if (msg.isUser)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, left: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (msg.isPending == true)
                            Text(
                              "Sending...",
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey,
                              ),
                            ),
                          if (msg.isFailed == true)
                            Text(
                              "❌ Failed",
                              style: TextStyle(fontSize: 10, color: Colors.red),
                            ),
                          if (msg.isPending == false && msg.isFailed != true)
                            Text(
                              "Sent ✅",
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.primary,
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
    }
    // 🧠 Summary Card
    else if (!msg.isUser &&
        msg.summaryType != null &&
        msg.summaryData != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: ChatSummaryCards(
          type: msg.summaryType!,
          data: msg.summaryData!,
          deviceId: widget.deviceId,
        ),
      );
    }
    // 💡 Prompt/Nudge bubble
    // 💡 Auto-playing voice nudges
    else if (!msg.isUser && msg.isPrompt == true && msg.voiceUrl != null) {
      if (!notifier.muteNudges) {
        notifier.enqueueNudge(msg);
      }
      final shouldHighlight = notifier.currentlyPlayingUrl == null;

      if (shouldHighlight) {
        notifier.currentlyPlayingUrl = msg.voiceUrl; // prevent re-trigger
        notifier.player.setUrl(msg.voiceUrl!).then((_) {
          notifier.player.play();
        });
      }
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            const CircleAvatar(
              radius: 16,
              backgroundImage: AssetImage('assets/splash/neura_logo.png'),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      msg.text ?? '',
                      style: const TextStyle(
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      _formatTimestamp(msg.timestamp),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
    // 💬 Normal Text Message
    else {
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
                    backgroundImage: AssetImage('assets/splash/neura_logo.png'),
                  ),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: GestureDetector(
                    onLongPress: () => _showReactionBar(context, msg),
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
                              "Emotion: ${msg.emotion}",
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          Text(
                            _formatTimestamp(msg.timestamp),
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                            ),
                          ),
                          if (msg.isUser)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (msg.isPending == true)
                                    Text(
                                      "Sending...",
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  if (msg.isFailed == true)
                                    Text(
                                      "❌ Failed",
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.red,
                                      ),
                                    ),
                                  if (msg.isPending == false &&
                                      msg.isFailed != true)
                                    Text(
                                      "Sent ✅",
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: theme.colorScheme.primary,
                                          ),
                                    ),
                                ],
                              ),
                            ),
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
    if (DateUtils.isSameDay(dt, now)) return TranslationService.tr("Today");
    return "${dt.day}/${dt.month}/${dt.year}";
  }

  bool _isSameDay(DateTime? a, DateTime? b) {
    if (a == null || b == null) return false;
    return DateUtils.isSameDay(a, b);
  }

  Widget _tierLimitWarningBanner(int used, int total) {
    final ratio = used / total;
    if (ratio >= 1.0) {
      return Container(
        padding: const EdgeInsets.all(12),
        color: Colors.red.shade100,
        child: Row(
          children: [
            const Icon(Icons.warning, color: Colors.red),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                TranslationService.tr(
                  "You've reached your monthly limit. Upgrade to continue chatting.",
                ),
                style: const TextStyle(color: Colors.red),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pushNamed(context, '/upgrade'),
              child: Text(TranslationService.tr("Upgrade")),
            ),
          ],
        ),
      );
    } else if (ratio >= 0.9) {
      return Container(
        padding: const EdgeInsets.all(12),
        color: Colors.orange.shade100,
        child: Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.orange),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                TranslationService.tr(
                  "You're nearing your monthly usage limit. Consider upgrading.",
                ),
                style: TextStyle(color: Colors.black87),
              ),
            ),
          ],
        ),
      );
    } else {
      return const SizedBox.shrink();
    }
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
    try {
      final isCurrentlyOn = chat.activeMode == "interpreter";
      final result = await toggleInterpreterMode(
        widget.deviceId,
        enable: !isCurrentlyOn,
      );

      final message = result["message"] ?? "Updated.";
      final newMode = result["active_mode"] ?? "manual";

      // ✅ Update local controller state
      chat.updateActiveMode(newMode);

      // ✅ Optionally persist
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString("active_mode", newMode);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Failed to toggle Interpreter Mode.")),
      );
    }
  }

  void _retryFCMTokenIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSent = prefs.getString('last_fcm_token');

    try {
      final currentToken = await FirebaseMessaging.instance.getToken();

      if (currentToken != null && currentToken != lastSent) {
        await DeviceService().retryFcmToken(currentToken);
        await prefs.setString('last_fcm_token', currentToken);
        debugPrint("✅ FCM token updated in chat screen");
      } else {
        debugPrint("ℹ️ FCM token already up-to-date or null");
      }
    } catch (e) {
      debugPrint("⚠️ FCM update in chat screen failed: $e");
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
        title: Text("${chat.aiName} ${TranslationService.tr("Mano-Mitram")}"),
        actions: [
          IconButton(
            icon: Icon(
              chat.muteNudges ? Icons.volume_off : Icons.volume_up,
              color: Colors.grey.shade700,
            ),
            tooltip: chat.muteNudges
                ? TranslationService.tr("Unmute Nudges")
                : TranslationService.tr("Mute Nudges"),
            onPressed: () {
              notifier.toggleNudgeMute();
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              notifier.disposeAudio();
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              if (mounted) Navigator.pushReplacementNamed(context, '/login');
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
                      return Column(
                        children: [
                          _tierLimitWarningBanner(used, total),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 4,
                            ),
                            child: TierUsageBar(used: used, total: total),
                          ),
                        ],
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
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
                        final lastBot = chat.messages.lastWhere(
                          (m) => !m.isUser,
                          orElse: () => ChatMessage(isUser: false),
                        );

                        if (lastBot.messagesRemaining != null &&
                            lastBot.messagesRemaining! <= 0) {
                          showDialog(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: Text(
                                TranslationService.tr("Limit Reached"),
                              ),
                              content: Text(
                                TranslationService.tr(
                                  "You've hit your monthly usage limit. Upgrade to continue.",
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: Text(TranslationService.tr("Cancel")),
                                ),
                                ElevatedButton(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    Navigator.pushNamed(context, '/upgrade');
                                  },
                                  child: const Text("Upgrade"),
                                ),
                              ],
                            ),
                          );
                          return; // Prevent sending
                        }

                        if (text.isNotEmpty) {
                          notifier.sendTextMessage(text);
                          _controller.clear();
                          // Auto-scroll
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
                  color: chat.isRecording
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
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
          // 🟨 Floating memory toggle on bottom-left
          Positioned(
            bottom: 20,
            left: 20,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 500),
              opacity:
                  1.0, // always visible; change this if you want conditional fade
              child: FloatingActionButton.small(
                onPressed: () async {
                  await _toggleMemory(
                    !memoryEnabled,
                  ); // should handle confirmation + state update
                },
                backgroundColor: memoryEnabled ? Colors.green : Colors.grey,
                tooltip: TranslationService.tr("Toggle Memory"),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, animation) =>
                      FadeTransition(opacity: animation, child: child),
                  child: Icon(
                    memoryEnabled ? Icons.memory : Icons.memory_outlined,
                    key: ValueKey(
                      memoryEnabled,
                    ), // this triggers AnimatedSwitcher
                    color: Colors.white,
                  ),
                ),
              ),
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
                    ? TranslationService.tr("Interpreter ON")
                    : TranslationService.tr("Interpreter OFF"),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: Colors.white,
                ),
              ),
              backgroundColor: chat.activeMode == "interpreter"
                  ? theme.colorScheme.primary
                  : theme.colorScheme.surfaceContainerHighest,
            ),
          ),
          // 🛡️ Floating Private Mode toggle (top-left)
          Positioned(
            top: 80,
            left: 20,
            child: FloatingActionButton.small(
              onPressed: _togglePrivateMode,
              backgroundColor: isPrivateMode ? Colors.red : Colors.grey,
              tooltip: TranslationService.tr("Private Mode"),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isPrivateMode ? Icons.lock : Icons.lock_open,
                    color: Colors.white,
                  ),
                  if (isPrivateMode && remainingPrivateMins > 0)
                    Text(
                      "$remainingPrivateMins m",
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
