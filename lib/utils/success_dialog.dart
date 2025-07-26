import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:vibration/vibration.dart';

class SuccessDialog extends StatelessWidget {
  final String title;
  final String subtitle;
  final String buttonText;
  final VoidCallback onButtonTap;

  const SuccessDialog({
    super.key,
    required this.title,
    required this.subtitle,
    required this.buttonText,
    required this.onButtonTap,
  });

  @override
  Widget build(BuildContext context) {
    // ✅ Trigger vibration only when dialog is built
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (await Vibration.hasVibrator()) {
        Vibration.vibrate(duration: 50); // subtle 50ms vibration
      }
    });
    return Dialog(
      backgroundColor: Colors.black,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Lottie.asset(
              'assets/neura_success_check.json',
              height: 120,
              repeat: false, // 🔁 Disable infinite loop
              animate: true, // ✅ Play once on load
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 16, color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.black,
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
              onPressed: onButtonTap,
              child: Text(buttonText),
            ),
          ],
        ),
      ),
    );
  }
}
