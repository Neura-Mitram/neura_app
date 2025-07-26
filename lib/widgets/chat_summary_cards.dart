import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neura_app/controllers/chat_provider.dart';

class ChatSummaryCards extends ConsumerWidget {
  final String type;
  final Map<String, dynamic> data;
  final String deviceId;

  const ChatSummaryCards({
    super.key,
    required this.type,
    required this.data,
    required this.deviceId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final chat = ref.watch(chatControllerProvider(deviceId));
    final isPro = chat.isPro; // ✅ tier check

    Widget content;

    switch (type) {
      case 'goal':
        content = _buildGoalCard(theme);
        break;
      case 'habit':
        content = _buildHabitCard(theme);
        break;
      case 'journal':
        content = _buildJournalCard(theme);
        break;
      case 'mood':
        content = _buildMoodCard(theme);
        break;
      case 'checkin':
        content = _buildCheckinCard(theme);
        break;
      case 'fallback':
        content = _buildFallbackCard(theme);
        break;
      default:
        content = const SizedBox.shrink();
    }

    // Only blur if not pro & not fallback type
    final isLocked = !isPro && type != 'fallback';

    return Stack(
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.dividerColor.withOpacity(0.2)),
          ),
          child: content,
        ),
        if (isLocked) _buildLockedOverlay(context, theme),
      ],
    );
  }

  Widget _buildGoalCard(ThemeData theme) {
    final title = data['title'] ?? 'Untitled Goal';
    final isCompleted = data['is_completed'] ?? false;
    final date = data['start_date'] ?? '';
    return Row(
      children: [
        Icon(Icons.flag, color: isCompleted ? Colors.green : Colors.orange),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.bodyLarge),
              Text(
                isCompleted ? 'Completed' : 'Ongoing since $date',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.hintColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHabitCard(ThemeData theme) {
    final desc = data['description'] ?? 'No details';
    final freq = data['frequency'] ?? 'Daily';
    return Row(
      children: [
        Icon(Icons.repeat, color: Colors.purple),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(desc, style: theme.textTheme.bodyLarge),
              Text('Frequency: $freq', style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildJournalCard(ThemeData theme) {
    final snippet = data['text'] ?? '[Empty journal]';
    return Row(
      children: [
        Icon(Icons.book, color: Colors.teal),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            snippet,
            style: theme.textTheme.bodyMedium,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildMoodCard(ThemeData theme) {
    final mood = data['mood'] ?? 'Unknown';
    final emoji = data['emoji'] ?? '🙂';
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 24)),
        const SizedBox(width: 10),
        Text('Mood: $mood', style: theme.textTheme.bodyLarge),
      ],
    );
  }

  Widget _buildCheckinCard(ThemeData theme) {
    final note = data['note'] ?? 'No note logged';
    final time = data['timestamp'];
    final timeStr = time != null
        ? DateFormat('hh:mm a').format(DateTime.parse(time))
        : '';
    return Row(
      children: [
        Icon(Icons.check_circle, color: Colors.blue),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(note, style: theme.textTheme.bodyLarge),
              if (timeStr.isNotEmpty)
                Text('Logged at $timeStr', style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFallbackCard(ThemeData theme) {
    final interpretation =
        data['meaning'] ?? 'No fallback explanation available.';
    return Row(
      children: [
        Icon(Icons.help_outline, color: Colors.grey),
        const SizedBox(width: 10),
        Expanded(
          child: Text(interpretation, style: theme.textTheme.bodyMedium),
        ),
      ],
    );
  }

  Widget _buildLockedOverlay(BuildContext context, ThemeData theme) {
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.85),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline, size: 40, color: Colors.grey),
            const SizedBox(height: 8),
            Text(
              "Pro Feature",
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
              ),
              onPressed: () {
                Navigator.pushNamed(
                  context,
                  "/upgrade",
                ); // or your upgrade screen route
              },
              child: const Text("Upgrade to Pro"),
            ),
          ],
        ),
      ),
    );
  }
}
