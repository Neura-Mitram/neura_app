import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/api_base.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Map<String, String>> getAuthHeaders() async {
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('auth_token') ?? "";
  return {'Authorization': 'Bearer $token'};
}

/// Send Message To Neura
Future<Map<String, dynamic>> sendMessageToNeura(
  String message,
  String deviceId,
) async {
  final headers = await getAuthHeaders();
  final payload = {'message': message, 'device_id': deviceId};

  final response = await http.post(
    Uri.parse('$Baseurl/chat/chat-with-neura'),
    headers: {...headers, 'Content-Type': 'application/json'},
    body: jsonEncode(payload),
  );

  if (response.statusCode == 200) {
    return jsonDecode(response.body);
  } else {
    throw Exception("Failed to get reply: ${response.body}");
  }
}

/// Active/Deactive Interpreter Mode
Future<Map<String, dynamic>> toggleInterpreterMode(
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

/// Active/Deactive Private Mode
Future<Map<String, dynamic>> getPrivateModeStatus(String deviceId) async {
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString("auth_token") ?? "";

  final res = await http.get(
    Uri.parse("$Baseurl/neura-pm/private-mode-status?device_id=$deviceId"),
    headers: {"Authorization": "Bearer $token"},
  );

  if (res.statusCode == 200) {
    final data = jsonDecode(res.body);
    return data['is_private'] ?? false;
  } else {
    throw Exception("Failed to fetch private mode status");
  }
}

/// Status Private Mode
Future<bool> togglePrivateMode(String deviceId, bool enable) async {
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString("auth_token") ?? "";

  final res = await http.post(
    Uri.parse("$Baseurl/neura-pm/private-mode"),
    headers: {
      "Authorization": "Bearer $token",
      "Content-Type": "application/json",
    },
    body: jsonEncode({"device_id": deviceId, "enable": enable}),
  );

  if (res.statusCode == 200) {
    final data = jsonDecode(res.body);
    return data['is_private'] ?? false;
  } else {
    throw Exception("Failed to toggle private mode");
  }
}
