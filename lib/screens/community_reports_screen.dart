import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_base.dart';
import '../services/community_alert_banner_service.dart';
import '../widgets/safe_route_card.dart';
import '../services/translation_service.dart';

class CommunityReportsScreen extends StatefulWidget {
  const CommunityReportsScreen({super.key});

  @override
  State<CommunityReportsScreen> createState() => _CommunityReportsScreenState();
}

class _CommunityReportsScreenState extends State<CommunityReportsScreen> {
  bool isLoading = true;
  bool showMyReports = false;
  Map<String, Map<String, Map<String, Map<String, List<dynamic>>>>>
  groupedReports = {};
  String aiSummary = '';
  String searchQuery = '';
  List<Map<String, dynamic>> safeRoute = [];
  String safeRouteTip = '';

  @override
  void initState() {
    super.initState();
    _fetchCommunityReports();
    _fetchCommunitySummary();
    _fetchSafeRoute();
  }

  Future<void> _fetchCommunityReports() async {
    setState(() => isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final deviceId = prefs.getInt('device_id');

    final uri = Uri.parse('$Baseurl/safety/community-reports');
    final res = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({"device_id": deviceId}),
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      final reports = data['grouped'] as Map<String, dynamic>;

      groupedReports = reports.map((state, cities) {
        return MapEntry(
          state,
          (cities as Map<String, dynamic>).map((city, areas) {
            return MapEntry(
              city,
              (areas as Map<String, dynamic>).map((area, streets) {
                return MapEntry(
                  area,
                  (streets as Map<String, dynamic>).map((street, entries) {
                    return MapEntry(street, entries as List<dynamic>);
                  }),
                );
              }),
            );
          }),
        );
      });

      setState(() => isLoading = false);
    } else {
      debugPrint("\u274c Error fetching community reports: \${res.body}");
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "\u274c ${TranslationService.tr("Failed to load community reports")}",
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _fetchCommunitySummary() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final deviceId = prefs.getInt('device_id');

    final uri = Uri.parse('$Baseurl/safety/community-summary');
    final res = await http.post(
      uri,
      headers: {'Authorization': 'Bearer $token'},
      body: jsonEncode({"device_id": deviceId}),
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      setState(() {
        aiSummary = data['summary'] ?? '';
      });
    }
  }

  Future<void> _fetchSafeRoute() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final deviceId = prefs.getInt('device_id');

    final uri = Uri.parse('$Baseurl/safety/safe-route');
    final res = await http.post(
      uri,
      headers: {'Authorization': 'Bearer $token'},
      body: {'device_id': deviceId.toString()},
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      if (data['success'] == true && data['route'] != null) {
        setState(() {
          safeRoute = List<Map<String, dynamic>>.from(data['route']);
          safeRouteTip = data['ai_tip'] ?? '';
        });
      }
    } else {
      debugPrint("\u274c Error fetching safe route: \${res.body}");
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(TranslationService.tr("Community Reports")),
        actions: [
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            tooltip: TranslationService.tr("Toggle My Reports / Community"),
            onPressed: () async {
              setState(() => showMyReports = !showMyReports);
              await _fetchCommunityReports();
              if (!showMyReports) await _fetchCommunitySummary();
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await _fetchCommunityReports();
              if (!showMyReports) await _fetchCommunitySummary();
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: TranslationService.tr("Search city or reason..."),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
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
          ? Center(child: Text(TranslationService.tr("No reports found.")))
          : RefreshIndicator(
              onRefresh: () async {
                await _fetchCommunityReports();
                if (!showMyReports) await _fetchCommunitySummary();
              },
              child: ListView(
                children: [
                  const CommunityAlertBanner(),
                  if (aiSummary.isNotEmpty && !showMyReports)
                    Card(
                      margin: const EdgeInsets.all(12),
                      color: theme.colorScheme.secondaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          "\ud83e\udde0 $aiSummary",
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ),
                  if (!showMyReports && safeRoute.isNotEmpty)
                    SafeRouteCard(safeRoute: safeRoute, aiTip: safeRouteTip),
                  ...groupedReports.entries.expand<Widget>((stateEntry) {
                    final state = stateEntry.key;
                    return [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          "\ud83d\udccd $state",
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      ...stateEntry.value.entries.expand<Widget>((cityEntry) {
                        final city = cityEntry.key;
                        if (!city.toLowerCase().contains(searchQuery) &&
                            searchQuery.isNotEmpty) {
                          return [];
                        }
                        return [
                          Padding(
                            padding: const EdgeInsets.only(
                              left: 16.0,
                              bottom: 4,
                            ),
                            child: Text(
                              "\u2514\u2500\u2500 $city",
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                          ...cityEntry.value.entries.expand<Widget>((
                            areaEntry,
                          ) {
                            final area = areaEntry.key;
                            return [
                              Padding(
                                padding: const EdgeInsets.only(
                                  left: 24.0,
                                  bottom: 4,
                                ),
                                child: Text(
                                  "    \u251c\u2500\u2500 $area",
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ),
                              ...areaEntry.value.entries.map<Widget>((
                                streetEntry,
                              ) {
                                final street = streetEntry.key;
                                final reports = streetEntry.value;
                                final latestTime = reports
                                    .map((r) => DateTime.parse(r['timestamp']))
                                    .reduce((a, b) => a.isAfter(b) ? a : b);
                                final formatted = DateFormat(
                                  'dd MMM, hh:mm a',
                                ).format(latestTime);

                                return ExpansionTile(
                                  title: Text(
                                    "        \u251c\u2500\u2500 $street (\${reports.length} Reports) \u2013 \ud83d\udd52 $formatted",
                                  ),
                                  children: reports.map<Widget>((r) {
                                    if (!r['reason']
                                            .toString()
                                            .toLowerCase()
                                            .contains(searchQuery) &&
                                        searchQuery.isNotEmpty) {
                                      return const SizedBox.shrink();
                                    }
                                    final time = DateFormat(
                                      'dd MMM, hh:mm a',
                                    ).format(DateTime.parse(r['timestamp']));
                                    return ListTile(
                                      title: Text(
                                        "\ud83d\udfe7 \${r['reason']} \u2013 $time",
                                      ),
                                      subtitle: Text(r['location'] ?? ''),
                                    );
                                  }).toList(),
                                );
                              }),
                            ];
                          }),
                        ];
                      }),
                    ];
                  }),
                ],
              ),
            ),
    );
  }
}
