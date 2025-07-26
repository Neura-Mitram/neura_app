import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_base.dart';

class TierService {
  /// Current tier
  Future<String> getCurrentTier() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('tier') ?? 'free'; // default fallback
  }

  /// Upgrade tier
  Future<void> upgradeTier({
    required String deviceId,
    required String newTier,
    required String paymentKey,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');

    if (token == null) throw Exception("No token found.");

    final response = await http.post(
      Uri.parse("$Baseurl/auth/upgrade-tier"),
      headers: {
        'Authorization': "Bearer $token",
        'Content-Type': "application/json",
      },
      body: jsonEncode({
        "device_id": deviceId,
        "new_tier": newTier,
        "payment_key": paymentKey,
      }),
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body);
      throw Exception("Upgrade failed: ${error['detail'] ?? response.body}");
    }

    // Save new tier
    await prefs.setString('tier', newTier);
  }

  /// Downgrade tier (only from pro -> basic)
  Future<void> downgradeTier({required String deviceId}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');

    if (token == null) throw Exception("No token found.");

    final response = await http.post(
      Uri.parse("$Baseurl/auth/downgrade-tier"),
      headers: {
        'Authorization': "Bearer $token",
        'Content-Type': "application/json",
      },
      body: jsonEncode({"device_id": deviceId, "new_tier": "basic"}),
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body);
      throw Exception("Downgrade failed: ${error['detail'] ?? response.body}");
    }

    // Save new tier
    await prefs.setString('tier', "basic");
  }
}
