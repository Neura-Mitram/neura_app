import '../models/chat_message.dart';

class ChatState {
  final List<ChatMessage> messages;
  final bool isListening;
  final bool isTyping;
  final bool micDisabled;
  final bool isSpeaking;
  final bool voiceUploadFailed;
  final bool isRetrying;
  final bool pendingMicRequest;
  final String? audioPath;
  final int recordingSeconds;

  const ChatState({
    this.messages = const [],
    this.isListening = false,
    this.isTyping = false,
    this.micDisabled = false,
    this.isSpeaking = false,
    this.voiceUploadFailed = false,
    this.isRetrying = false,
    this.pendingMicRequest = false,
    this.audioPath,
    this.recordingSeconds = 0,
  });

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? isListening,
    bool? isTyping,
    bool? micDisabled,
    bool? isSpeaking,
    bool? voiceUploadFailed,
    bool? isRetrying,
    bool? pendingMicRequest,
    String? audioPath,
    int? recordingSeconds,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isListening: isListening ?? this.isListening,
      isTyping: isTyping ?? this.isTyping,
      micDisabled: micDisabled ?? this.micDisabled,
      isSpeaking: isSpeaking ?? this.isSpeaking,
      voiceUploadFailed: voiceUploadFailed ?? this.voiceUploadFailed,
      isRetrying: isRetrying ?? this.isRetrying,
      pendingMicRequest: pendingMicRequest ?? this.pendingMicRequest,
      audioPath: audioPath ?? this.audioPath,
      recordingSeconds: recordingSeconds ?? this.recordingSeconds,
    );
  }
}

