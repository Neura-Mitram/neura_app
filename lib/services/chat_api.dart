import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/api_base.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Map<String, String>> getAuthHeaders() async {
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('auth_token') ?? "";
  return {'Authorization': 'Bearer $token'};
}

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
