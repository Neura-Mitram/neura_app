import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/api_base.dart';
import '../services/translation_service.dart';
import '../widgets/setup_progress_stepper.dart';

class SosContactScreen extends StatefulWidget {
  const SosContactScreen({super.key});

  @override
  State<SosContactScreen> createState() => _SosContactScreenState();
}

class _SosContactScreenState extends State<SosContactScreen> {
  List<Map<String, dynamic>> contacts = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchContacts();

    // ✅ Load translations for preferred language
    WidgetsBinding.instance.addPostFrameCallback((_) {
      TranslationService.loadScreenOnInit(context, "sos-contact", onDone: () {
        setState(() {});
      });
    });
  }

  Future<void> _fetchContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final deviceId = prefs.getInt('device_id');

    final uri = Uri.parse('$Baseurl/safety/list-sos-contacts');
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
      setState(() {
        contacts = List<Map<String, dynamic>>.from(data['contacts']);
        isLoading = false;
      });
    } else {
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(TranslationService.tr("❌ Failed to load SOS contacts")),
        ),
      );
    }
  }

  void _addContactDialog() {
    if (contacts.length >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            TranslationService.tr("You can only save up to 3 SOS contacts."),
          ),
        ),
      );
      return;
    }

    final nameController = TextEditingController();
    final phoneController = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(TranslationService.tr("Add SOS Contact")),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: TranslationService.tr('Name'),
              ),
            ),
            TextField(
              controller: phoneController,
              decoration: InputDecoration(
                labelText: TranslationService.tr('Phone'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(TranslationService.tr("Cancel")),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.trim().isEmpty ||
                  phoneController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      TranslationService.tr(
                        "Please enter both name and phone number.",
                      ),
                    ),
                  ),
                );
                return;
              }
              _addContact(nameController.text, phoneController.text);
              Navigator.pop(context);
            },
            child: Text(TranslationService.tr("Save")),
          ),
        ],
      ),
    );
  }

  Future<void> _addContact(String name, String phone) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final deviceId = prefs.getInt('device_id');

    final uri = Uri.parse('$Baseurl/safety/add-sos-contact');
    final res = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({"device_id": deviceId, "name": name, "phone": phone}),
    );

    if (res.statusCode == 200) {
      _fetchContacts();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(TranslationService.tr("❌ Failed to add contact")),
        ),
      );
    }
  }

  Future<void> _deleteContact(int contactId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final deviceId = prefs.getInt('device_id');

    final uri = Uri.parse('$Baseurl/safety/delete-sos-contact');
    final res = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({"device_id": deviceId, "contact_id": contactId}),
    );

    if (res.statusCode == 200) {
      _fetchContacts();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(TranslationService.tr("❌ Failed to delete contact")),
        ),
      );
    }
  }

  Widget _nextButton(bool isSmall) {
    return Padding(
      padding: EdgeInsets.all(isSmall ? 12.0 : 16.0),
      child: ElevatedButton(
        onPressed: contacts.isNotEmpty
            ? () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('sos_contacts_completed', true);
                Navigator.pushNamed(context, '/wakeword');
              }
            : null,
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          textStyle: TextStyle(fontSize: isSmall ? 14 : 16),
        ),
        child: Text(TranslationService.tr("Next")),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmall = screenWidth < 360;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          TranslationService.tr("My SOS Contacts"),
          style: TextStyle(fontSize: isSmall ? 18 : 20),
        ),
      ),
      body: Column(
        children: [
          const SetupProgressStepper(currentStep: SetupStep.sos),
          SizedBox(height: isSmall ? 8 : 12),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : contacts.isEmpty
                    ? Center(
                        child: Text(
                          TranslationService.tr("No contacts added."),
                          style: TextStyle(fontSize: isSmall ? 14 : 16),
                        ),
                      )
                    : ListView.builder(
                        itemCount: contacts.length,
                        itemBuilder: (context, index) {
                          final c = contacts[index];
                          return ListTile(
                            leading: Icon(
                              Icons.contact_phone,
                              color: theme.colorScheme.primary,
                            ),
                            title: Text(
                              c['name'] ?? '',
                              style: TextStyle(fontSize: isSmall ? 14 : 16),
                            ),
                            subtitle: Text(
                              c['phone'] ?? '',
                              style: TextStyle(fontSize: isSmall ? 12 : 14),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () => _deleteContact(c['id']),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addContactDialog,
        backgroundColor: theme.colorScheme.primary,
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: _nextButton(isSmall),
    );
  }
}
