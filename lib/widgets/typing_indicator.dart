import 'package:flutter/material.dart';

class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _dot1, _dot2, _dot3;

  @override
  void initState() {
    super.initState();
    _controller =
    AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat();

    _dot1 = Tween<double>(begin: 0, end: 8).animate(
        CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.6, curve: Curves.easeInOut)));
    _dot2 = Tween<double>(begin: 0, end: 8).animate(
        CurvedAnimation(parent: _controller, curve: const Interval(0.2, 0.8, curve: Curves.easeInOut)));
    _dot3 = Tween<double>(begin: 0, end: 8).animate(
        CurvedAnimation(parent: _controller, curve: const Interval(0.4, 1.0, curve: Curves.easeInOut)));
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 24,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDot(_dot1.value),
            const SizedBox(width: 4),
            _buildDot(_dot2.value),
            const SizedBox(width: 4),
            _buildDot(_dot3.value),
          ],
        ),
      ),
    );
  }

  Widget _buildDot(double height) {
    return Container(
      width: 6,
      height: 6 + height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
