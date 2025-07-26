import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_base.dart';

/// Fetch All Profile Summary
Future<Map<String, dynamic>> fetchProfileSummary() async {
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('auth_token');

  if (token == null) return {};

  try {
    final res = await http.get(
      Uri.parse("$Baseurl/profile-summary"),
      headers: {"Authorization": "Bearer $token"},
    );

    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    } else {
      print("❌ Failed to fetch profile-summary: ${res.statusCode}");
    }
  } catch (e) {
    print("❌ Exception in fetchProfileSummary: $e");
  }

  return {};
}

/// Fetch All Profile Emotional Summary
Future<List<Map<String, dynamic>>> fetchEmotionSummary({
  required String startDate,
  required String endDate,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('auth_token');

  if (token == null) return [];

  try {
    final res = await http.get(
      Uri.parse(
        "$Baseurl/emotion-summary?start_date=$startDate&end_date=$endDate",
      ),
      headers: {"Authorization": "Bearer $token"},
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      return List<Map<String, dynamic>>.from(data["summary"]);
    } else {
      print("❌ Failed to fetch emotion summary: ${res.statusCode}");
    }
  } catch (e) {
    print("❌ Exception in fetchEmotionSummary: $e");
  }

  return [];
}

/// Fetch Memory
Future<Map<String, dynamic>?> fetchMemory({
  bool importantOnly = false,
  String? emotionFilter,
  DateTime? startDate,
  DateTime? endDate,
  required int offset,
  required int limit,
}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString("auth_token");
    final deviceId = prefs.getString("device_id");

    final body = {
      "device_id": deviceId,
      "limit": limit,
      "offset": offset,
      "important_only": importantOnly,
      "emotion_filter": emotionFilter,
    };

    final res = await http.post(
      Uri.parse("$Baseurl/memory/memory-log"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      },
      body: jsonEncode(body),
    );

    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }
  } catch (e) {
    print("Memory fetch failed: $e");
  }
  return null;
}

/// Delete Memory
Future<bool> deleteMemory() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString("auth_token");
    final deviceId = prefs.getString("device_id");

    final res = await http.delete(
      Uri.parse("$Baseurl/memory/delete?device_id=$deviceId"),
      headers: {"Authorization": "Bearer $token"},
    );
    return res.statusCode == 200;
  } catch (e) {
    print("Delete memory error: $e");
    return false;
  }
}

/// Export Memory
Future<List<Map<String, dynamic>>?> exportMemory() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString("auth_token");
    final deviceId = prefs.getString("device_id");

    final res = await http.get(
      Uri.parse("$Baseurl/memory/export?device_id=$deviceId"),
      headers: {"Authorization": "Bearer $token"},
    );

    if (res.statusCode == 200) {
      return List<Map<String, dynamic>>.from(jsonDecode(res.body));
    }
  } catch (e) {
    print("Export memory error: $e");
  }
  return null;
}

/// Memory Cache Clean
Future<void> cacheMemory(List<Map<String, dynamic>> data) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('cached_memory', jsonEncode(data));
}

/// Get Memory From Cache
Future<List<Map<String, dynamic>>?> getCachedMemory() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString("cached_memory");
  if (raw == null) return null;
  return List<Map<String, dynamic>>.from(jsonDecode(raw));
}

/// Mark Important From Cache
Future<bool> markImportant({
  required int messageId,
  required bool important,
}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString("auth_token");
    final deviceId = prefs.getString("device_id");

    final res = await http.post(
      Uri.parse("$Baseurl/memory/mark-important"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      },
      body: jsonEncode({
        "device_id": deviceId,
        "message_id": messageId,
        "important": important,
      }),
    );
    return res.statusCode == 200;
  } catch (e) {
    print("Mark important error: $e");
    return false;
  }
}

/// Get Memory Status
Future<bool> getCurrentMemoryStatus() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString("auth_token");
    final deviceId = prefs.getString("device_id");

    final res = await http.post(
      Uri.parse("$Baseurl/memory/memory-log"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      },
      body: jsonEncode({"device_id": deviceId, "limit": 1, "offset": 0}),
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      return data["memory_enabled"] == true;
    }
  } catch (e) {
    print("Failed to fetch memory status: $e");
  }
  return false; // fallback if error
}

// Toggle Memory
Future<bool> toggleMemory({required bool enabled}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    final deviceId = prefs.getString('device_id');

    if (token == null || deviceId == null) return false;

    final uri = Uri.parse('$Baseurl/memory/toggle-memory');
    final res = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'device_id': deviceId, 'enabled': enabled}),
    );

    if (res.statusCode == 200) {
      return jsonDecode(res.body)['memory_enabled'] == enabled;
    }
  } catch (e) {
    print("Toggle memory error: $e");
  }
  return false;
}

// Export Personality
Future<Map<String, dynamic>?> fetchPersonalitySnapshot() async {
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('auth_token');
  final deviceId = prefs.getString('device_id');

  final url = Uri.parse("$Baseurl/export/personality?device_id=$deviceId");

  final response = await http.get(
    url,
    headers: {"Authorization": "Bearer $token"},
  );

  if (response.statusCode == 200) {
    return jsonDecode(response.body);
  } else {
    print("❌ Failed to fetch personality snapshot: ${response.body}");
    return null;
  }
}
