import 'package:local_auth/local_auth.dart';
import 'package:flutter/material.dart';

Future<bool> authenticateUser(BuildContext context) async {
  final LocalAuthentication auth = LocalAuthentication();
  bool isAuthenticated = false;

  try {
    isAuthenticated = await auth.authenticate(
      localizedReason: 'Please authenticate to confirm you’re safe',
      options: const AuthenticationOptions(biometricOnly: false),
    );
  } catch (e) {
    print("Biometric auth error: $e");
  }

  if (!isAuthenticated) {
    // Fallback to PIN entry
    final pinCorrect = await _showPinPrompt(context);
    return pinCorrect;
  }

  return isAuthenticated;
}

Future<bool> _showPinPrompt(BuildContext context) async {
  String enteredPin = '';
  final correctPin = '4259'; // Replace with secure server-fetch or local encrypted

  return await showDialog<bool>(
    context: context,
    builder: (_) {
      return AlertDialog(
        title: const Text("Enter 4-digit PIN"),
        content: TextField(
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 4,
          onChanged: (value) => enteredPin = value,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          ElevatedButton(onPressed: () => Navigator.pop(context, enteredPin == correctPin), child: const Text("Confirm")),
        ],
      );
    },
  ) ?? false;
}
