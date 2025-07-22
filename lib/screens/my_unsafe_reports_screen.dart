import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import '../services/api_base.dart';
import '../services/community_alert_banner_service.dart';
import '../services/translation_service.dart';

class MyUnsafeReportsScreen extends StatefulWidget {
  const MyUnsafeReportsScreen({super.key});

  @override
  State<MyUnsafeReportsScreen> createState() => _MyUnsafeReportsScreenState();
}

class _MyUnsafeReportsScreenState extends State<MyUnsafeReportsScreen> {
  Map<String, Map<String, Map<String, Map<String, List<dynamic>>>>>
  groupedReports = {};
  bool isLoading = true;
  String searchQuery = '';
  final Map<String, GlobalKey> _tileKeys = {};
  String? unsafeSummary;

  @override
  void initState() {
    super.initState();
    _fetchReports();
    _fetchUnsafeSummary();
  }

  Future<void> _fetchReports() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      final deviceId = prefs.getInt('device_id');

      final uri = Uri.parse("$Baseurl/safety/my-reports");
      final response = await http.post(
        uri,
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
        body: jsonEncode({"device_id": deviceId}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final reports = (data['reports'] as List).reversed.toList();
        await _groupReportsByLocation(reports);
        setState(() => isLoading = false);
      } else {
        throw Exception("Failed to fetch reports");
      }
    } catch (e) {
      debugPrint("Error fetching reports: $e");
      setState(() => isLoading = false);
    }
  }

  Future<void> _groupReportsByLocation(List reports) async {
    groupedReports.clear();
    for (var report in reports) {
      final lat = report['latitude'];
      final lon = report['longitude'];
      if (lat == null || lon == null) continue;

      try {
        final placemarks = await placemarkFromCoordinates(lat, lon);
        final p = placemarks.first;
        final state = p.administrativeArea?.trim() ?? 'Unknown State';
        final city = p.locality?.trim() ?? 'Unknown City';
        final area = p.subLocality?.trim() ?? 'Unknown Area';
        final street = p.street?.trim() ?? 'Unknown Street';

        groupedReports.putIfAbsent(state, () => {});
        groupedReports[state]!.putIfAbsent(city, () => {});
        groupedReports[state]![city]!.putIfAbsent(area, () => {});
        groupedReports[state]![city]![area]!
            .putIfAbsent(street, () => [])
            .add(report);
      } catch (_) {
        groupedReports.putIfAbsent('Unknown State', () => {});
        groupedReports['Unknown State']!.putIfAbsent('Unknown City', () => {});
        groupedReports['Unknown State']!['Unknown City']!.putIfAbsent(
          'Unknown Area',
          () => {},
        );
        groupedReports['Unknown State']!['Unknown City']!['Unknown Area']!
            .putIfAbsent('Unknown Street', () => [])
            .add(report);
      }
    }
  }

  Future<void> _deleteReport(int reportId, BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final deviceId = prefs.getInt("device_id");
    final token = prefs.getString("token");

    if (deviceId == null || token == null) return;

    final uri = Uri.parse("$Baseurl/safety/delete-report");

    final response = await http.post(
      uri,
      headers: {"Authorization": "Bearer $token"},
      body: {
        "device_id": deviceId.toString(),
        "report_id": reportId.toString(),
      },
    );

    if (response.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(TranslationService.tr("✅ Report deleted")),
          backgroundColor: Colors.green,
        ),
      );
      await _fetchReports();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(TranslationService.tr("❌ Failed to delete")),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _confirmDelete(int reportId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(TranslationService.tr("Confirm Delete")),
        content: Text(
          TranslationService.tr("Are you sure you want to delete this report?"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(TranslationService.tr("Cancel")),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteReport(reportId, context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(TranslationService.tr("Delete")),
          ),
        ],
      ),
    );
  }

  Future<void> _scrollToNearestLocation(BuildContext context) async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(TranslationService.tr("Location permission denied")),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            TranslationService.tr(
              "Location permission permanently denied. Please enable it from settings.",
            ),
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString("token");
      if (token == null) return;

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final uri = Uri.parse(
        "$Baseurl/safety/nearest-location?latitude=${position.latitude}&longitude=${position.longitude}",
      );
      final res = await http.get(
        uri,
        headers: {"Authorization": "Bearer $token"},
      );

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final targetCity = data["city"] ?? "";
        final targetArea = data["area"] ?? "";
        _scrollToCityArea(targetCity, targetArea, context);
      }
    } catch (e) {
      debugPrint("❌ Error in jump to nearest: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(TranslationService.tr("Location check failed")),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _scrollToCityArea(String city, String area, BuildContext context) {
    final targetKey = "$city|$area";
    final key = _tileKeys[targetKey];
    if (key != null) {
      Scrollable.ensureVisible(
        key.currentContext!,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(TranslationService.tr("No reports nearby")),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _fetchUnsafeSummary() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString("token");
      final deviceId = prefs.getInt("device_id");

      if (token == null || deviceId == null) return;

      final uri = Uri.parse("$Baseurl/safety/unsafe-summary");
      final response = await http.post(
        uri,
        headers: {"Authorization": "Bearer $token"},
        body: {"device_id": deviceId.toString()},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() => unsafeSummary = data["summary"]);
      }
    } catch (e) {
      debugPrint("Error fetching unsafe summary: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(TranslationService.tr('My Unsafe Reports')),
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            tooltip: TranslationService.tr("Jump to nearby reports"),
            onPressed: () => _scrollToNearestLocation(context),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(40),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: TranslationService.tr('Search city or keyword...'),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(),
              ),
              onChanged: (val) =>
                  setState(() => searchQuery = val.toLowerCase()),
            ),
          ),
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : groupedReports.isEmpty
          ? Center(child: Text(TranslationService.tr("No reports yet.")))
          : Column(
              children: [
                const CommunityAlertBanner(),
                if (unsafeSummary != null)
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Card(
                      color: Colors.orange.shade50,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.warning_amber_rounded,
                              color: Colors.orange,
                              size: 28,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                unsafeSummary!,
                                style: const TextStyle(fontSize: 15),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: ListView(
                    children: groupedReports.entries.expand<Widget>((
                      stateEntry,
                    ) {
                      final state = stateEntry.key;
                      return <Widget>[
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            "📍 $state",
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        ...stateEntry.value.entries.expand<Widget>((cityEntry) {
                          final city = cityEntry.key;
                          if (!city.toLowerCase().contains(searchQuery) &&
                              searchQuery.isNotEmpty)
                            return <Widget>[];
                          return <Widget>[
                            Padding(
                              padding: const EdgeInsets.only(
                                left: 16.0,
                                bottom: 4,
                              ),
                              child: Text(
                                "└── $city",
                                style: const TextStyle(fontSize: 16),
                              ),
                            ),
                            ...cityEntry.value.entries.expand<Widget>((
                              areaEntry,
                            ) {
                              final area = areaEntry.key;
                              return <Widget>[
                                Padding(
                                  padding: const EdgeInsets.only(
                                    left: 24.0,
                                    bottom: 4,
                                  ),
                                  child: Text(
                                    "    ├── $area",
                                    style: const TextStyle(fontSize: 15),
                                  ),
                                ),
                                ...areaEntry.value.entries.map<Widget>((
                                  streetEntry,
                                ) {
                                  final street = streetEntry.key;
                                  final areaReports = streetEntry.value;
                                  final tileKey = GlobalKey();
                                  _tileKeys["$city|$area"] = tileKey;
                                  return ExpansionTile(
                                    key: tileKey,
                                    title: Text(
                                      "        ├── $street (${areaReports.length} ${TranslationService.tr("Reports")})",
                                    ),
                                    children: areaReports.map<Widget>((r) {
                                      final time = DateFormat(
                                        'dd MMM, hh:mm a',
                                      ).format(DateTime.parse(r['timestamp']));
                                      return ListTile(
                                        title: Text(
                                          "🟧 ${r['reason']} – $time",
                                        ),
                                        subtitle: Text(r['location'] ?? ''),
                                        trailing: IconButton(
                                          icon: const Icon(
                                            Icons.delete,
                                            color: Colors.redAccent,
                                          ),
                                          onPressed: () =>
                                              _confirmDelete(r['id']),
                                        ),
                                      );
                                    }).toList(),
                                  );
                                }).toList(),
                              ];
                            }).toList(),
                          ];
                        }).toList(),
                      ];
                    }).toList(),
                  ),
                ),
              ],
            ),
    );
  }
}
