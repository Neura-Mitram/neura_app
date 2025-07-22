import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

class AnimatedWaveformBars extends StatefulWidget {
  final bool isRecording;
  const AnimatedWaveformBars({super.key, required this.isRecording});

  @override
  State<AnimatedWaveformBars> createState() => _AnimatedWaveformBarsState();
}

class _AnimatedWaveformBarsState extends State<AnimatedWaveformBars> {
  late Timer _timer;
  List<double> heights = List.generate(10, (_) => 10);

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 150), (_) {
      if (widget.isRecording) {
        setState(() {
          heights = List.generate(10, (_) => Random().nextDouble() * 25 + 5);
        });
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: heights
          .map((h) => Container(
        width: 4,
        height: h,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
        ),
      ))
          .toList(),
    );
  }
}
