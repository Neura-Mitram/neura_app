import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class NeuraLoader extends StatelessWidget {
  final String message;

  const NeuraLoader({super.key, this.message = "Neura is getting ready..."});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Lottie.asset(
              'assets/neura_voicewave_loader.lottie',
              height: 200,
              repeat: true,
            ),
            const SizedBox(height: 20),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
