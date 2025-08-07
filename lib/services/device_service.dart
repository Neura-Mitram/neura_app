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

  /// Returns Android SDK version (API level) or 0 if not Android
  Future<int> get sdkVersion async {
    if (!Platform.isAndroid) return 0;
    
    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;
    return androidInfo.version.sdkInt;
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

  /// Update device + FCM TOKEN info to backend
  Future<void> updateDeviceContextWithFcm({
    required String? fcmToken,
    String? outputAudioMode,
    String? preferredDeliveryMode,
    String? deviceToken,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    final deviceId = prefs.getString('device_id');
  
    if (deviceId == null || token == null) {
      throw Exception("Missing device ID or token");
    }
  
    final platform = _getPlatform();
    final osVersion = await _getOsVersion();
  
    final uri = Uri.parse("$Baseurl/update-device-context");
  
    final body = {
      "device_id": deviceId,
      "device_type": platform,
      "os_version": osVersion,
      "output_audio_mode": outputAudioMode ?? 'speaker',
      "preferred_delivery_mode": preferredDeliveryMode ?? 'text',
      "device_token": deviceToken ?? '',
    };
  
    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      if (fcmToken != null) 'X-FCM-Token': fcmToken,  // Custom FCM header
    };
  
    final response = await http.post(
      uri,
      headers: headers,
      body: jsonEncode(body),
    );
  
    if (response.statusCode != 200) {
      final error = jsonDecode(response.body);
      throw Exception("Update failed: ${error['detail'] ?? response.body}");
    }
  
    print("✅ Device + FCM context updated with JSON.");
  }


  /// Retry FCM TOKEN info to backend
  Future<void> retryFcmToken(String fcmToken) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    final deviceId = prefs.getString('device_id');

    if (token == null || deviceId == null) {
      throw Exception("Missing auth or device ID");
    }

    final uri = Uri.parse("$Baseurl/retry-device-fcm");
    final request = http.MultipartRequest('POST', uri)
      ..fields['token'] = fcmToken
      ..fields['device_id'] = deviceId
      ..headers['Authorization'] = 'Bearer $token';

    final response = await http.Response.fromStream(await request.send());

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body);
      throw Exception("FCM update failed: ${error['detail'] ?? response.body}");
    }
  }

// Add this method to check if app is running on an emulator
  Future<bool> isRunningOnEmulator() async {
    if (!Platform.isAndroid) return false;

    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;

    return !androidInfo.isPhysicalDevice ||
          (androidInfo.brand.toLowerCase().contains("generic")) ||
          (androidInfo.product.toLowerCase().contains("sdk"));
  }

}
