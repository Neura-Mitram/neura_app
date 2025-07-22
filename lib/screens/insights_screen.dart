import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/api_base.dart';
import '../services/translation_service.dart';

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
  bool isLoading = true;
  bool showCurrentMonth = true;

  @override
  void initState() {
    super.initState();
    _loadTogglePreference();
    _fetchInsights();
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
    setState(() {
      isLoading = true;
    });

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    final userId = prefs.getInt('user_id');

    if (token == null || userId == null) {
      setState(() {
        isLoading = false;
      });
      return;
    }

    try {
      final profileRes = await http.get(
        Uri.parse("$Baseurl/profile-summary"),
        headers: {"Authorization": "Bearer $token"},
      );

      if (profileRes.statusCode == 200) {
        final profile = jsonDecode(profileRes.body);
        gptUsed = profile["monthly_gpt_count"] ?? 0;
        voiceUsed = profile["monthly_voice_count"] ?? 0;
        creatorUsed = profile["monthly_creator_count"] ?? 0;
        joinDate = DateFormat.yMMMd().format(
          DateTime.parse(profile["created_at"]),
        );
        final lastActive = DateTime.parse(profile["last_active_at"]);
        final now = DateTime.now();
        final streak = now.difference(lastActive).inDays == 0 ? 1 : 0;
        streakInfo = "$streak day streak";
      }

      final today = DateTime.now();
      final startDate = DateFormat(
        "yyyy-MM-dd",
      ).format(today.subtract(const Duration(days: 30)));
      final endDate = DateFormat("yyyy-MM-dd").format(today);

      final emotionRes = await http.get(
        Uri.parse(
          "$Baseurl/emotion-summary?start_date=$startDate&end_date=$endDate",
        ),
        headers: {"Authorization": "Bearer $token"},
      );

      if (emotionRes.statusCode == 200) {
        final emotionData = jsonDecode(emotionRes.body);
        emotionSummary = List<Map<String, dynamic>>.from(
          emotionData["summary"],
        );
      }
    } catch (e) {
      print("Error fetching insights: $e");
    }

    setState(() {
      isLoading = false;
    });
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
          backgroundColor: theme.dividerColor,
          color: theme.colorScheme.primary,
        ),
      ],
    );
  }

  Widget _emotionChart() {
    if (emotionSummary.isEmpty) {
      return Text(TranslationService.tr("No emotion data available."));
    }

    return SizedBox(
      height: 200,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              tooltipPadding: const EdgeInsets.all(8),
              tooltipMargin: 8,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final emotion = emotionSummary[group.x.toInt()]["emotion"];
                final count = rod.toY.toInt();
                return BarTooltipItem(
                  "$emotion: $count",
                  const TextStyle(
                    color: Colors.white,
                    backgroundColor: Colors.black87, // ✅ Applies background
                  ),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, _) {
                  final index = value.toInt();
                  if (index >= 0 && index < emotionSummary.length) {
                    return Text(
                      emotionSummary[index]["emotion"]
                          .substring(0, 3)
                          .toUpperCase(),
                      style: const TextStyle(fontSize: 10),
                    );
                  }
                  return const Text("");
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(emotionSummary.length, (index) {
            return BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: (emotionSummary[index]["count"] as num).toDouble(),
                  color: Theme.of(context).colorScheme.primary,
                  width: 16,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            );
          }),
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
        title: Text(
          TranslationService.tr("Insights"),
          style: theme.textTheme.titleLarge,
        ),
        backgroundColor: theme.appBarTheme.backgroundColor,
        foregroundColor: theme.appBarTheme.foregroundColor,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(24),
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
                        TranslationService.tr("Emotion Trends (Last 30 Days)"),
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
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Text(TranslationService.tr("This Month")),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Text(TranslationService.tr("Last Month")),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _emotionChart(),
                ],
              ),
            ),
    );
  }
}
