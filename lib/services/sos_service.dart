import 'package:flutter/services.dart';

class SosService {
  static const MethodChannel _channel = MethodChannel("sos.sms.native");

  static Future<void> triggerSafeSms({required String message}) async {
    try {
      await _channel.invokeMethod("sendSilentSms", {"message": message});
    } catch (e) {
      print("❌ Failed to open SMS: $e");
    }
  }
}
