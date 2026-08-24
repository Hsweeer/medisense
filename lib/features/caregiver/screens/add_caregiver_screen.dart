import 'package:contacts_service_plus/contacts_service_plus.dart' as cs;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/services/caregiver_service.dart';
import '../../../data/models/caregiver_models.dart';

class AddCaregiverScreen extends StatefulWidget {
  const AddCaregiverScreen({super.key});

  @override
  State<AddCaregiverScreen> createState() => _AddCaregiverScreenState();
}

class _AddCaregiverScreenState extends State<AddCaregiverScreen> {
  final _searchController = TextEditingController();
  List<AppUserSummary> _searchResults = [];
  bool _searching = false;
  bool _notRegistered = false;
  String? _lastQuery;

  Future<void> _onSearchChanged(String query) async {
    _lastQuery = query;
    if (query.trim().length < 2) {
      setState(() {
        _searchResults = [];
        _notRegistered = false;
      });
      return;
    }
    setState(() => _searching = true);
    final results = await CaregiverService.instance.searchUsers(query);
    if (!mounted || _lastQuery != query) return;
    setState(() {
      _searchResults = results;
      _notRegistered = results.isEmpty;
      _searching = false;
    });
  }

  Future<void> _pickFromContacts() async {
    final granted = await Permission.contacts.request();
    if (!granted.isGranted) return;

    final contacts = await cs.ContactsService.getContacts();
    if (!mounted) return;

    final picked = await showModalBottomSheet<cs.Contact>(
      context: context,
      builder: (_) => ListView(
        children: contacts
            .where((c) => c.phones?.isNotEmpty == true)
            .map(
              (c) => ListTile(
                title: Text(c.displayName ?? 'Unknown'),
                subtitle: Text(c.phones!.first.value ?? ''),
                onTap: () => Navigator.pop(context, c),
              ),
            )
            .toList(),
      ),
    );
    if (picked == null || !mounted) return;

    final phone = picked.phones?.first.value ?? '';
    final match = await CaregiverService.instance.findByPhone(phone);

    if (match == null) {
      _showInvite(picked.displayName ?? 'This contact');
    } else {
      _confirmAndSend(match);
    }
  }

  void _showInvite(String name) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('$name doesn\'t have MediSense yet'),
        content: const Text('Invite them to download the app and try again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(context);
              // Share.share('Get MediSense: https://medisense.app/download');
            },
            icon: const Icon(Icons.share),
            label: const Text('Share invite'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmAndSend(AppUserSummary recipient) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Send request to ${recipient.name}?'),
        content: const Text(
          'They\'ll be able to see and accept a request for you to manage their reminders.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send request'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await CaregiverService.instance.sendRequest(recipient);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Request sent to ${recipient.name}')),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add caregiver contact')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search by name, phone, username, or email',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.contacts_rounded),
            title: const Text('Pick from phone contacts'),
            onTap: _pickFromContacts,
          ),
          const Divider(),
          if (_searching) const LinearProgressIndicator(),
          if (_notRegistered && !_searching)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No matching MediSense account found.'),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: _searchResults.length,
              itemBuilder: (_, i) {
                final user = _searchResults[i];
                return ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(user.name),
                  subtitle: Text(user.phone),
                  trailing: FilledButton(
                    onPressed: () => _confirmAndSend(user),
                    child: const Text('Request'),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
