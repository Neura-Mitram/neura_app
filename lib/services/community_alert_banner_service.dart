import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_base.dart';

class CommunityAlertBanner extends StatefulWidget {
  const CommunityAlertBanner({super.key});

  @override
  State<CommunityAlertBanner> createState() => _CommunityAlertBannerState();
}

class _CommunityAlertBannerState extends State<CommunityAlertBanner> {
  List<dynamic> clusters = [];
  bool isChecking = true;

  @override
  void initState() {
    super.initState();
    _checkForNearbyClusters();
  }

  Future<void> _checkForNearbyClusters() async {
    setState(() => isChecking = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString("token");
      final deviceId = prefs.getInt("device_id");

      if (token == null || deviceId == null) return;

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final uri = Uri.parse("$Baseurl/safety/cluster-check");
      final res = await http.post(uri,
          headers: {
            "Authorization": "Bearer $token",
            "Content-Type": "application/json"
          },
          body: jsonEncode({
            "device_id": deviceId,
            "latitude": position.latitude,
            "longitude": position.longitude
          })
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() => clusters = data['clusters'] ?? []);
      }
    } catch (e) {
      debugPrint("❌ Cluster check error: $e");
    }
    setState(() => isChecking = false);
  }

  @override
  Widget build(BuildContext context) {
    if (isChecking || clusters.isEmpty) return const SizedBox.shrink();

    final top = clusters.first;
    final street = top['street'];
    final count = top['count'];
    final time = DateFormat('hh:mm a').format(DateTime.parse(top['latest']));

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Card(
        color: Colors.red[50],
        child: ListTile(
          leading: const Icon(Icons.warning, color: Colors.redAccent),
          title: Text("🚨 $count reports near $street"),
          subtitle: Text("Latest report at $time"),
          trailing: IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _checkForNearbyClusters,
          ),
        ),
      ),
    );
  }
}
