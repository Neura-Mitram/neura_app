import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'api_base.dart';
import 'dart:io';

class AuthService {
  /// Anonymous login using device_id
  Future<Map<String, dynamic>> anonymousLogin(String deviceId) async {
    final response = await http.post(
      Uri.parse("$Baseurl/auth/anonymous-login"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"device_id": deviceId}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final user = data["user"];

      if (user == null) {
        throw Exception("Anonymous login failed: user object is null.");
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', data["token"]);
      await prefs.setInt('user_id', user["id"]);
      await prefs.setString('device_id', user["device_id"] ?? deviceId);
      await prefs.setString('ai_name', user["ai_name"] ?? "Neura");
      await prefs.setString('voice', user["voice"] ?? "female");
      await prefs.setString('tier', user["tier"] ?? "free");

      // ✅ Return user map so caller can use it
      return user;
    } else {
      throw Exception("Anonymous login failed: ${response.body}");
    }
  }

  /// Update onboarding details
  Future<Map<String, dynamic>> updateOnboarding({
    required String deviceId,
    required String aiName,
    required String voice,
    required String preferredLang,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');

    if (token == null) throw Exception("Missing token");

    final response = await http.post(
      Uri.parse("$Baseurl/auth/update-onboarding"),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      },
      body: jsonEncode({
        "device_id": deviceId,
        "ai_name": aiName,
        "voice": voice,
        "preferred_lang": preferredLang,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception("Onboarding update failed: ${response.body}");
    }

    return jsonDecode(response.body); // ✅ Return full JSON payload
  }

  /// Upload Wake words details
  Future<String> uploadWakewordSamples({
    required String deviceId,
    required List<File> audioSamples,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');

    if (token == null) throw Exception("Missing token");
    if (audioSamples.length != 3) throw Exception("3 audio samples required");

    final request = http.MultipartRequest(
      "POST",
      Uri.parse("$Baseurl/wakeword/train"),
    );

    request.headers["Authorization"] = "Bearer $token";
    request.fields["device_id"] = deviceId;
    request.fields["wakeword_label"] =
        "neura"; // 🔁 You can make this dynamic later

    // Rename fields to match backend: file1, file2, file3
    request.files.add(
      await http.MultipartFile.fromPath("file1", audioSamples[0].path),
    );
    request.files.add(
      await http.MultipartFile.fromPath("file2", audioSamples[1].path),
    );
    request.files.add(
      await http.MultipartFile.fromPath("file3", audioSamples[2].path),
    );

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      throw Exception("Wakeword upload failed: ${response.body}");
    }

    final json = jsonDecode(response.body);

    return json['model_path'];
  }

  /// Download Wake words details
  Future<String?> downloadWakewordModel(String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    final response = await http.get(
      Uri.parse('$Baseurl/wakeword/download-model?device_id=$deviceId'),
      headers: {"Authorization": "Bearer $token"},
    );

    if (response.statusCode == 200) {
      final dir = await getApplicationDocumentsDirectory();
      final filePath = "${dir.path}/wakeword_model.tflite";
      final file = File(filePath);
      await file.writeAsBytes(response.bodyBytes);
      return filePath; // ✅ use this path to load into TFLite later
    } else {
      throw Exception("Failed to download wakeword model: ${response.body}");
    }
  }

  /// Update updateUserLang details
  Future<Map<String, dynamic>> updateUserLang({
    required String preferredLang,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final deviceId = prefs.getString('device_id');
    final token = prefs.getString('auth_token');

    if (token == null) throw Exception("Missing token");

    final response = await http.post(
      Uri.parse("$Baseurl/change-user-language"),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      },
      body: jsonEncode({
        "device_id": deviceId,
        "preferred_lang": preferredLang,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception("Onboarding update failed: ${response.body}");
    }

    return jsonDecode(response.body); // ✅ Return full JSON payload
  }

  /// Active/Deactive Interpreter Mode
  static Future<Map<String, dynamic>> toggleInterpreterMode(
    String deviceId, {
    required bool enable,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString("auth_token") ?? "";

    final response = await http.post(
      Uri.parse("$Baseurl/ws/toggle-interpreter-mode"),
      headers: {"Authorization": "Bearer $token"},
      body: {"device_id": deviceId, "enable": enable.toString()},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Failed to toggle Interpreter Mode.");
    }
  }

  /// Update Translate UI as per user
  Future<Map<String, String>> translateUIStrings({
    required List<String> keys,
    required String targetLang,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    final deviceId = prefs.getString('device_id');

    if (token == null || deviceId == null) {
      throw Exception("Missing auth token or device ID");
    }

    final response = await http.post(
      Uri.parse("$Baseurl/auth/translate-ui"),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      },
      body: jsonEncode({
        "device_id": deviceId, // ✅ Now included
        "strings": keys,
        "target_lang": targetLang,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception("Translation failed: ${response.body}");
    }

    final data = jsonDecode(response.body);

    if (data['preferred_lang'] != null) {
      await prefs.setString('preferred_lang', data['preferred_lang']);
    }

    return Map<String, String>.from(data['translations']);
  }
}
