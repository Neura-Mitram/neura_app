
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/profile_service.dart';
import '../services/translation_service.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_saver/file_saver.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  int gptUsed = 0;
  int voiceUsed = 0;
  int creatorUsed = 0;
  int monthlyLimit = 30;
  String joinDate = "";
  String streakInfo = "0 days";
  List<Map<String, dynamic>> emotionSummary = [];
  Map<String, double> traitScores = {};
  bool isLoading = true;
  bool showCurrentMonth = true;
  Map<String, dynamic>? _personalitySnapshot;

  @override
  void initState() {
    super.initState();
    _loadTogglePreference();
    _fetchInsights();

    // ✅ Load translations for preferred language
    WidgetsBinding.instance.addPostFrameCallback((_) {
    TranslationService.loadScreenOnInit(context, "insights", onDone: () {
      setState(() {}); // optional if you want to refresh UI
      });
    });
  }

  Future<void> _loadTogglePreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      showCurrentMonth = prefs.getBool('showCurrentMonth') ?? true;
    });
  }

  Future<void> _saveTogglePreference(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('showCurrentMonth', value);
  }

  Future<void> _fetchInsights() async {
    setState(() => isLoading = true);
    try {
      final profile = await fetchProfileSummary();
      if (profile.isNotEmpty) {
        gptUsed = profile["monthly_gpt_count"] ?? 0;
        voiceUsed = profile["monthly_voice_count"] ?? 0;
        creatorUsed = profile["monthly_creator_count"] ?? 0;
        joinDate = DateFormat.yMMMd().format(
          DateTime.parse(profile["created_at"]),
        );

        final lastActive = DateTime.parse(profile["last_active_at"]);
        final now = DateTime.now();
        final streak = now.difference(lastActive).inDays == 0 ? 1 : 0;
        TranslationService.tr(
          "{count} day streak",
        ).replaceFirst("{count}", "$streak");
      }

      final today = DateTime.now();
      final startDate = DateFormat(
        "yyyy-MM-dd",
      ).format(today.subtract(const Duration(days: 30)));
      final endDate = DateFormat("yyyy-MM-dd").format(today);

      emotionSummary = await fetchEmotionSummary(
        startDate: startDate,
        endDate: endDate,
      );

      // ✅ Use ProfileService to fetch snapshot
      final data = await fetchPersonalitySnapshot();
      if (data != null) {
        _personalitySnapshot = data;
        final traits = data['top_traits'] as List<dynamic>;
        traitScores = {
          for (var trait in traits)
            trait['trait']: (trait['score'] as num).toDouble(),
        };
      }
    } catch (e) {
      debugPrint("❌ Error fetching insights: $e");
    }
    setState(() => isLoading = false);
  }

  Future<void> _exportPersonality(Map<String, dynamic> data) async {
  try {
    final formatted = const JsonEncoder.withIndent('  ').convert(data);
    final bytes = Uint8List.fromList(utf8.encode(formatted));

    final String? path = await FileSaver.instance.saveFile(
      name: "neura_personality_snapshot.txt", // ✅ include extension in name
      bytes: bytes,
      mimeType: MimeType.text, // ✅ or MimeType.other with custom
    );

    if (path != null && path.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("✅ Snapshot saved to Downloads.")),
      );
    }
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("❌ Failed to save file: $e")),
    );
  }
}

  Widget _progressBar(String label, int used, int total) {
    final theme = Theme.of(context);
    final percent = (used / total).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("$label: $used / $total", style: theme.textTheme.bodyMedium),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: percent,
          minHeight: 8,
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
          color: theme.colorScheme.primary,
        ),
      ],
    );
  }

  Widget _lineChart() {
    if (emotionSummary.isEmpty) {
      return Text(TranslationService.tr("No emotion data available."));
    }

    final colors = {
      'happy': Colors.green,
      'sad': Colors.blue,
      'angry': Colors.red,
    };

    final grouped = <String, List<FlSpot>>{};
    for (int i = 0; i < emotionSummary.length; i++) {
      final emotion = emotionSummary[i]['emotion'];
      final count = (emotionSummary[i]['count'] as num).toDouble();
      grouped.putIfAbsent(emotion, () => []).add(FlSpot(i.toDouble(), count));
    }

    return SizedBox(
      height: 250,
      child: LineChart(
        LineChartData(
          gridData: FlGridData(show: true),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, _) {
                  final index = value.toInt();
                  if (index < emotionSummary.length) {
                    return Text(
                      emotionSummary[index]['emotion']
                          .substring(0, 2)
                          .toUpperCase(),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true)),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: grouped.entries.map((entry) {
            return LineChartBarData(
              isCurved: true,
              color: colors[entry.key],
              spots: entry.value,
              dotData: FlDotData(show: false),
              belowBarData: BarAreaData(show: false),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _traitChart() {
    if (traitScores.isEmpty) {
      return Text(TranslationService.tr("No personality data available."));
    }

    return SizedBox(
      height: 250,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          barGroups: traitScores.entries.map((e) {
            return BarChartGroupData(
              x: traitScores.keys.toList().indexOf(e.key),
              barRods: [
                BarChartRodData(
                  toY: e.value,
                  width: 20,
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            );
          }).toList(),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, _) {
                  final index = value.toInt();
                  final name = traitScores.keys.elementAt(index);
                  return Text(name.substring(0, 3).toUpperCase());
                },
              ),
            ),
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true)),
          ),
          borderData: FlBorderData(show: false),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(TranslationService.tr("Insights")),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: TranslationService.tr("Export Personality"),
            onPressed: () {
              if (_personalitySnapshot != null) {
                _exportPersonality(_personalitySnapshot!);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      TranslationService.tr("Snapshot not ready yet"),
                    ),
                  ),
                );
              }
            },
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(24),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      TranslationService.tr("Usage Overview"),
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
                    _progressBar(
                      TranslationService.tr("Text Messages"),
                      gptUsed,
                      monthlyLimit,
                    ),
                    const SizedBox(height: 12),
                    _progressBar(
                      TranslationService.tr("Voice Messages"),
                      voiceUsed,
                      monthlyLimit,
                    ),
                    const SizedBox(height: 12),
                    _progressBar(
                      TranslationService.tr("Creator Usage"),
                      creatorUsed,
                      monthlyLimit,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      "${TranslationService.tr("Your Streak")}: $streakInfo",
                      style: theme.textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "${TranslationService.tr("Joined")}: $joinDate",
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          TranslationService.tr("Emotion Trends"),
                          style: theme.textTheme.titleLarge,
                        ),
                        ToggleButtons(
                          borderRadius: BorderRadius.circular(12),
                          isSelected: [showCurrentMonth, !showCurrentMonth],
                          onPressed: (index) {
                            setState(() {
                              showCurrentMonth = index == 0;
                            });
                            _saveTogglePreference(showCurrentMonth);
                          },
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Text(TranslationService.tr("This Month")),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Text(TranslationService.tr("Last Month")),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _lineChart(),
                    const SizedBox(height: 24),
                    Text(
                      TranslationService.tr("Personality Traits"),
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    _traitChart(),
                  ],
                ),
              ),
            ),
    );
  }
}
