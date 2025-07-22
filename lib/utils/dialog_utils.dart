import 'package:flutter/material.dart';
import '../widgets/neura_loader.dart'; // adjust path as needed
import '../utils/success_dialog.dart'; // Make sure the path is correct

/// ✅ Shows the Neura animated loader with a message
void showNeuraLoading(BuildContext context, [String message = "Please wait..."]) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => NeuraLoader(message: message),
  );
}

/// ❌ Shows a branded error dialog
void showNeuraError(BuildContext context, String errorMessage) {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text("Oops! Something went wrong"),
      content: Text(errorMessage),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      actions: [
        TextButton(
          child: const Text("OK", style: TextStyle(fontWeight: FontWeight.bold)),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    ),
  );
}

/// ❌ Shows customizable error dialog
Future<void> showErrorDialog(BuildContext context, {required String title, required String message}) {
  return showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          child: const Text("OK"),
          onPressed: () => Navigator.of(context).pop(),
        )
      ],
    ),
  );
}

/// ✅ Shows the animated Neura customizable success dialog (Lottie-based)
Future<void> showNeuraSuccessDialog(
    BuildContext context, {
      required String title,
      required String subtitle,
      required String buttonText,
      required VoidCallback onButtonTap,
    }) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => SuccessDialog(
      title: title,
      subtitle: subtitle,
      buttonText: buttonText,
      onButtonTap: onButtonTap,
    ),
  );
}
