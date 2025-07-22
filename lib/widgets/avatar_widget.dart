import 'package:flutter/material.dart';

class AssistantAvatar extends StatelessWidget {
  final String voice;        // "male" or "female"
  final bool isSpeaking;     // true = speaking.png, false = listening.png
  final double size;

  const AssistantAvatar({
    required this.voice,
    required this.isSpeaking,
    this.size = 130.0, // 👈 Increased size here
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final imagePath = 'assets/avatars/${voice}_${isSpeaking ? "speaking" : "listening"}.png';

    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 1.0, end: isSpeaking ? 1.15 : 1.0),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
        builder: (context, scale, child) {
          return Stack(
            alignment: Alignment.center,
            children: [
              // 🔵 Glow ring
              AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                width: size * 1.4,
                height: size * 1.4,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSpeaking
                      ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1 * 255)
                      : Colors.transparent,
                  boxShadow: isSpeaking
                      ? [
                    BoxShadow(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5 * 255),
                      blurRadius: 25,
                      spreadRadius: 4,
                    ),
                  ]
                      : [],
                ),
              ),

              // 🧠 Main avatar
              Transform.scale(
                scale: scale,
                child: ClipOval(
                  child: Image.asset(
                    imagePath,
                    height: size,
                    width: size,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
