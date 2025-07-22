import 'dart:io';
import 'dart:convert';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_base.dart';

class DeviceService {
  /// Returns platform name
  String _getPlatform() {
    if (Platform.isAndroid) return "android";
    if (Platform.isIOS) return "ios";
    return "unknown";
  }

  /// Returns OS version string
  Future<String> _getOsVersion() async {
    final deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      return androidInfo.version.release;
    }
    if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      return iosInfo.systemVersion;
    }
    return "";
  }

  /// Returns a unique device ID
  Future<String> getDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      final fingerprint = androidInfo.fingerprint;
      final model = androidInfo.model;
      return "$fingerprint-$model";
    }
    if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      return iosInfo.identifierForVendor ?? "unknown_device";
    }
    return "unsupported_platform";
  }

  /// Update device info to backend
  Future<void> updateDeviceContext({
    String? outputAudioMode,
    String? preferredDeliveryMode,
    String? deviceToken,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    final deviceId = prefs.getString('device_id');

    if (deviceId == null) {
      throw Exception("No device Id found. Please log in first.");
    }

    final platform = _getPlatform();
    final osVersion = await _getOsVersion();

    final payload = {
      "device_id": deviceId,
      "device_type": platform,
      "os_version": osVersion,
      "device_token": deviceToken ?? "",
      "output_audio_mode": outputAudioMode ?? "speaker",
      "preferred_delivery_mode": preferredDeliveryMode ?? "text",
    };

    final response = await http.post(
      Uri.parse("$Baseurl/update-device"),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      },
      body: jsonEncode(payload),
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body);
      throw Exception(
        "Device update failed: ${error['detail'] ?? response.body}",
      );
    }

    print("✅ Device context updated successfully.");
  }
}
