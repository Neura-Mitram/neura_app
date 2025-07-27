import 'package:flutter/material.dart';

class SafeRouteCard extends StatelessWidget {
  final List<Map<String, dynamic>> safeRoute;
  final String? aiTip;

  const SafeRouteCard({super.key, required this.safeRoute, this.aiTip});

  Color _riskColor(String risk) {
    switch (risk) {
      case 'low':
        return Colors.green;
      case 'medium':
        return Colors.orange;
      case 'high':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (safeRoute.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Card(
        color: Colors.lightGreen[50],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "🛣️ Safe Route Suggestion",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...safeRoute.map((step) {
                final color = _riskColor(step['risk'] ?? 'unknown');
                return ListTile(
                  leading: Icon(Icons.place, color: color),
                  title: Text(step['location'] ?? 'Unknown'),
                  subtitle: step['warning'] != null
                      ? Text("⚠️ ${step['warning']}",
                      style: const TextStyle(color: Colors.orange))
                      : null,
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      (step['risk'] ?? 'UNKNOWN').toUpperCase(),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: color,
                        fontSize: 12,
                      ),
                    ),
                  ),
                );
              }),
              if (aiTip != null && aiTip!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text("🧠 $aiTip",
                      style: const TextStyle(
                          fontStyle: FontStyle.italic, fontSize: 13)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
