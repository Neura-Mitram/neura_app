import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../controllers/chat_controller.dart';

/// This provider manages the ChatController for the whole app.
/// It automatically loads preferences when instantiated.

final chatControllerProvider = ChangeNotifierProvider.family<ChatController, String>((ref, deviceId) {
  final controller = ChatController(deviceId: deviceId);
  controller.loadPreferences();
  return controller;
});
