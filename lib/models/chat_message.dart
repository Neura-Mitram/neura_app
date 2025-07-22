class ChatMessage {
  final String? text;
  final bool isUser;
  final bool isVoice;
  final String? voiceUrl;
  final Duration? duration;
  final String? emotion;           // 🎯 New
  final int? messagesUsed;         // 🎯 New
  final int? messagesRemaining;    // 🎯 New
  final DateTime timestamp;
  final List<String>? suggestions; // ✅ NEW
  bool? isPending;
  bool? isFailed;
  String? reaction;
  final Map<String, dynamic>? rawData;


  ChatMessage({
    this.text,
    required this.isUser,
    this.isVoice = false,
    this.voiceUrl,
    this.duration,
    this.emotion,
    this.messagesUsed,
    this.messagesRemaining,
    this.suggestions, // ✅ This line connects the constructor parameter
    this.isPending,
    this.isFailed,
    this.reaction,
    this.rawData,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}
