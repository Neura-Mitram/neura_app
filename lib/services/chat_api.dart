import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../services/api_base.dart';
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';


Future<Map<String, String>> getAuthHeaders() async {
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('auth_token') ?? "";
  return {
    'Authorization': 'Bearer $token',
  };
}

Future<Map<String, dynamic>> sendMessageToNeura(String message, String deviceId) async {
  final headers = await getAuthHeaders();
  final payload = {
    'message': message,
    'device_id': deviceId,
  };

  final response = await http.post(
    Uri.parse('$Baseurl/chat/chat-with-neura'),
    headers: {
      ...headers,
      'Content-Type': 'application/json',
    },
    body: jsonEncode(payload),
  );

  if (response.statusCode == 200) {
    return jsonDecode(response.body);
  } else {
    throw Exception("Failed to get reply: ${response.body}");
  }
}

Future<Map<String, dynamic>> sendVoiceToNeura(File file, String deviceId) async {
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('auth_token') ?? "";

  final uri = Uri.parse('$Baseurl/voice/voice-chat-with-neura');
  final request = http.MultipartRequest('POST', uri)
    ..fields['device_id'] = deviceId
    ..headers['Authorization'] = 'Bearer $token'
    ..files.add(await http.MultipartFile.fromPath(
      'file',
      file.path,
      contentType: MediaType('audio', 'wav'),
    ));

  final streamedResponse = await request.send();
  final response = await http.Response.fromStream(streamedResponse);

  if (response.statusCode == 200) {
    return json.decode(response.body);
  } else {
    throw Exception("Voice API failed: ${response.statusCode}\nBody: ${response.body}");
  }
}

