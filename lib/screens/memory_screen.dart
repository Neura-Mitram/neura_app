import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../services/translation_service.dart';
import '../services/profile_service.dart';
import 'dart:convert';

class MemoryScreen extends StatefulWidget {
  const MemoryScreen({super.key});

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  List<Map<String, dynamic>> messages = [];
  bool isLoading = true;
  bool importantOnly = false;
  String? emotionFilter;
  bool memoryEnabled = true;
  bool sortDescending = true;
  DateTime? startDate;
  DateTime? endDate;
  int offset = 0;
  final int limit = 20;
  bool isFetchingMore = false;
  bool hasMore = true;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadCachedMemory();
    _loadMemoryStatus();
    _fetchMemory(reset: true);
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
              _scrollController.position.maxScrollExtent - 100 &&
          !isFetchingMore &&
          hasMore) {
        _fetchMemory();
      }
    });
  }

  Future<void> _loadMemoryStatus() async {
    final status = await getCurrentMemoryStatus();
    if (status != null) {
      setState(() => memoryEnabled = status);
    }
  }

  Future<void> _loadCachedMemory() async {
    final cached = await getCachedMemory();
    if (cached != null) {
      setState(() {
        messages = cached;
      });
    }
  }

  Future<void> _fetchMemory({bool reset = false}) async {
    if (reset) {
      setState(() {
        offset = 0;
        messages.clear();
        hasMore = true;
      });
    }

    setState(() {
      isLoading = reset;
      isFetchingMore = !reset;
    });

    final data = await fetchMemory(
      importantOnly: importantOnly,
      emotionFilter: emotionFilter,
      startDate: startDate,
      endDate: endDate,
      limit: limit,
      offset: offset,
    );

    if (data != null) {
      memoryEnabled = data['memory_enabled'] ?? true;
      final fetched = List<Map<String, dynamic>>.from(data['messages']);
      if (!sortDescending) fetched.reversed;
      setState(() {
        messages.addAll(fetched);
        offset += fetched.length;
        hasMore = fetched.length == limit;
      });
      await cacheMemory(messages);
    }
    setState(() {
      isLoading = false;
      isFetchingMore = false;
    });
  }

  Future<void> _deleteMemory() async {
    final success = await deleteMemory();
    if (success) {
      setState(() => messages.clear());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(TranslationService.tr("Memory deleted successfully.")),
        ),
      );
    }
  }

  Future<void> _exportMemory({bool saveToFile = false}) async {
    final data = await exportMemory();
    if (data != null) {
      final prettyJson = JsonEncoder.withIndent('  ').convert(data);
      if (saveToFile) {
        final directory = await FilePicker.platform.getDirectoryPath();
        if (directory != null) {
          final file = File("$directory/neura_memory_export.json");
          await file.writeAsString(prettyJson);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                TranslationService.tr(
                  "File saved to {path}",
                ).replaceFirst("{path}", directory),
              ),
            ),
          );
        }
        return;
      }
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(TranslationService.tr("Exported Memory")),
          content: SingleChildScrollView(child: Text(prettyJson)),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: prettyJson));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(TranslationService.tr("Copied to clipboard")),
                  ),
                );
              },
              child: Text(TranslationService.tr("Copy")),
            ),
            TextButton(
              onPressed: () async => await Share.share(prettyJson),
              child: Text(TranslationService.tr("Share")),
            ),
            TextButton(
              onPressed: () async => await _exportMemory(saveToFile: true),
              child: Text(TranslationService.tr("Save as File")),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(TranslationService.tr("Close")),
            ),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(TranslationService.tr("Failed to export memory.")),
        ),
      );
    }
  }

  String emotionIcon(String? label) {
    switch (label?.toLowerCase()) {
      case 'happy':
        return "😊";
      case 'sad':
        return "😢";
      case 'angry':
        return "😡";
      default:
        return "😐";
    }
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        startDate = picked.start;
        endDate = picked.end;
      });
      await _fetchMemory(reset: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(TranslationService.tr("Memory")),
        actions: [
          if (memoryEnabled)
            IconButton(
              icon: Icon(
                sortDescending ? Icons.arrow_downward : Icons.arrow_upward,
              ),
              onPressed: () {
                setState(() {
                  sortDescending = !sortDescending;
                  messages = messages.reversed.toList();
                });
              },
              tooltip: TranslationService.tr("Toggle Sort Order"),
            ),
          IconButton(
            icon: const Icon(Icons.date_range),
            onPressed: _pickDateRange,
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : memoryEnabled
          ? Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: SwitchListTile(
                    title: Text(TranslationService.tr("Memory Enabled")),
                    value: memoryEnabled,
                    onChanged: (v) async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: Text(
                            v
                                ? TranslationService.tr("Enable Memory?")
                                : TranslationService.tr("Disable Memory?"),
                          ),
                          content: Text(
                            v
                                ? TranslationService.tr(
                                    "Neura will start remembering your conversations.",
                                  )
                                : TranslationService.tr(
                                    "Neura will stop remembering conversations.",
                                  ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: Text(TranslationService.tr("Cancel")),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: Text(TranslationService.tr("Confirm")),
                            ),
                          ],
                        ),
                      );

                      if (confirmed == true) {
                        final updated = await toggleMemory(
                          enabled: v,
                        ); // ✅ FIXED
                        if (updated) {
                          setState(() => memoryEnabled = v);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                v
                                    ? TranslationService.tr("Memory enabled.")
                                    : TranslationService.tr("Memory disabled."),
                              ),
                            ),
                          );
                        }
                      }
                    },
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    itemCount: messages.length + (hasMore ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i == messages.length) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }
                      final msg = messages[i];
                      return ListTile(
                        title: Text(msg['message']),
                        subtitle: Text(
                          "${msg['sender']} • ${emotionIcon(msg['emotion_label'])} ${msg['emotion_label'] ?? 'neutral'}\n${DateFormat.yMMMd().add_jm().format(DateTime.parse(msg['timestamp']))}",
                        ),
                        trailing: msg['important'] == true
                            ? IconButton(
                                icon: const Icon(
                                  Icons.star,
                                  color: Colors.amber,
                                ),
                                onPressed: () async {
                                  final updated = await markImportant(
                                    messageId: msg['id'],
                                    important: false,
                                  );
                                  if (updated) _fetchMemory(reset: true);
                                },
                              )
                            : IconButton(
                                icon: const Icon(Icons.star_border),
                                onPressed: () async {
                                  final updated = await markImportant(
                                    messageId: msg['id'],
                                    important: true,
                                  );
                                  if (updated) _fetchMemory(reset: true);
                                },
                              ),
                      );
                    },
                  ),
                ),
              ],
            )
          : Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(TranslationService.tr("Memory is currently disabled.")),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            TranslationService.tr(
                              "Please enable memory from settings.",
                            ),
                          ),
                        ),
                      );
                    },
                    child: Text(TranslationService.tr("Enable Memory")),
                  ),
                ],
              ),
            ),
      floatingActionButton: memoryEnabled
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.extended(
                  onPressed: () => _exportMemory(saveToFile: false),
                  label: Text(TranslationService.tr("Export")),
                  icon: const Icon(Icons.download),
                ),
                const SizedBox(height: 12),
                FloatingActionButton.extended(
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: Text(TranslationService.tr("Delete Memory")),
                        content: Text(
                          TranslationService.tr(
                            "Are you sure you want to delete all saved memory?",
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: Text(TranslationService.tr("Cancel")),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: Text(TranslationService.tr("Delete")),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) _deleteMemory();
                  },
                  backgroundColor: Colors.red,
                  icon: const Icon(Icons.delete),
                  label: Text(TranslationService.tr("Clear")),
                ),
              ],
            )
          : null,
    );
  }
}

extension StringExtension on String {
  String capitalize() => this[0].toUpperCase() + substring(1);
}
