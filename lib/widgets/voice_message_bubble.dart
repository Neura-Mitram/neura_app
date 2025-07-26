import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';

class VoiceMessageBubble extends StatefulWidget {
  final String audioUrl;
  final Duration duration;
  final DateTime? timestamp;
  final bool showDateHeader;
  final String? emotion;
  final VoidCallback? onPlaybackComplete;
  final bool isHighlighted;

  const VoiceMessageBubble({
    super.key,
    required this.audioUrl,
    required this.duration,
    this.timestamp,
    this.showDateHeader = false,
    this.emotion,
    this.onPlaybackComplete,
    this.isHighlighted = false,
  });

  @override
  State<VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<VoiceMessageBubble> {
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  Duration _currentPosition = Duration.zero;
  Timer? _waveTimer;
  Timer? _fadeTimer;
  StreamSubscription<Duration>? _positionSub;

  List<double> _waveformValues = List.generate(20, (_) => 0);
  final List<double> _staticWaveform = [
    8,
    14,
    10,
    18,
    6,
    12,
    16,
    10,
    8,
    6,
    14,
    12,
    10,
    6,
    8,
    16,
    14,
    10,
    12,
    6,
  ];

  @override
  void initState() {
    super.initState();

    _positionSub = _player.positionStream.listen((pos) {
      setState(() => _currentPosition = pos);
    });

    _player.playerStateStream.listen((state) async {
      if (state.processingState == ProcessingState.completed) {
        await _player.stop();
        _resetPlayback();
        widget.onPlaybackComplete?.call();
      }
    });
  }

  void _resetPlayback() {
    _waveTimer?.cancel();
    _fadeTimer?.cancel();
    setState(() {
      _isPlaying = false;
      _waveformValues = _staticWaveform;
      _currentPosition = Duration.zero;
    });
  }

  @override
  void dispose() {
    _waveTimer?.cancel();
    _fadeTimer?.cancel();
    _positionSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    if (_isPlaying) {
      await _player.pause();
      _waveTimer?.cancel();
      setState(() => _isPlaying = false);
      return;
    }

    try {
      await _player.stop();
      await _player.setUrl(widget.audioUrl);
      await _player.setVolume(0.0);
      await _player.play();
      _startWaveformAnimation();
      _fadeInVolume();

      setState(() => _isPlaying = true);
    } catch (e) {
      debugPrint("❌ Voice message playback failed: $e");
    }
  }

  void _fadeInVolume() {
    _fadeTimer?.cancel();
    _fadeTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      final vol = (_player.volume + 0.1).clamp(0.0, 1.0);
      _player.setVolume(vol);
      if (vol >= 1.0) timer.cancel();
    });
  }

  void _startWaveformAnimation() {
    _waveTimer?.cancel();
    _waveTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (_isPlaying) {
        setState(() {
          _waveformValues = List.generate(
            20,
            (_) => Random().nextDouble() * 14 + 6,
          );
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bars = _isPlaying ? _waveformValues : _staticWaveform;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showDateHeader && widget.timestamp != null)
          Padding(
            padding: const EdgeInsets.only(left: 12.0, bottom: 4.0, top: 8.0),
            child: Text(
              _dateHeader(widget.timestamp!),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withAlpha(153),
              ),
            ),
          ),
        Container(
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: widget.isHighlighted
                ? theme.colorScheme.primary.withOpacity(0.25)
                : theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(20),
            boxShadow: widget.isHighlighted
                ? [
                    BoxShadow(
                      color: theme.colorScheme.primary.withOpacity(0.4),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ]
                : [],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: _togglePlayback,
                    onLongPress: () async {
                      await _player.stop();
                      _resetPlayback();
                    },
                    child: Icon(
                      _isPlaying ? Icons.pause : Icons.play_arrow,
                      color: theme.colorScheme.onPrimary,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Row(
                    children: bars.map((height) {
                      return Container(
                        width: 3,
                        height: height,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.onPrimary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _formatDuration(
                      _isPlaying ? _currentPosition : widget.duration,
                    ),
                    style: TextStyle(
                      color: theme.colorScheme.onPrimary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              if (widget.emotion != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onPrimary.withAlpha(30),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      "Emotion: ${widget.emotion}",
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onPrimary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (widget.timestamp != null)
          Padding(
            padding: const EdgeInsets.only(left: 16.0),
            child: Text(
              _formatTimestamp(widget.timestamp!),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withAlpha(153),
              ),
            ),
          ),
      ],
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatTimestamp(DateTime dt) {
    return DateFormat('hh:mm a').format(dt);
  }

  String _dateHeader(DateTime dt) {
    final now = DateTime.now();
    if (DateUtils.isSameDay(now, dt)) return "Today";
    return DateFormat('dd MMM yyyy').format(dt);
  }
}
