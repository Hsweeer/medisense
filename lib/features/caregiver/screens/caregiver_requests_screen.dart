import 'package:flutter/material.dart';

import '../../../core/services/caregiver_service.dart';
import '../../../data/models/caregiver_models.dart';
import 'add_caregiver_screen.dart';
import 'create_caregiver_reminder_screen.dart';

class CaregiverRequestsScreen extends StatelessWidget {
  const CaregiverRequestsScreen({super.key});

  Future<void> _revoke(BuildContext context, CaregiverLink link) async {
    final cancelExisting = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Restrict ${link.senderName}?'),
        content: Text(
          '${link.senderName} won\'t be able to create new reminders for you. '
              'Do you also want to cancel reminders they already created?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep existing reminders'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel those too'),
          ),
        ],
      ),
    );
    if (cancelExisting == null) return;

    await CaregiverService.instance.revokeAccess(link.id);
    if (cancelExisting) {
      await CaregiverService.instance.cancelRemindersFrom(link.senderUid);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Caregiver requests'),
        actions: [
          IconButton(
            tooltip: 'Send a new request',
            icon: const Icon(Icons.person_add_alt_1),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AddCaregiverScreen()),
            ),
          ),
        ],
      ),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Pending requests',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          StreamBuilder<List<CaregiverLink>>(
            stream: CaregiverService.instance.incomingRequests(),
            builder: (context, snapshot) {
              final requests = snapshot.data ?? [];
              if (requests.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No pending requests.'),
                );
              }
              return Column(
                children: requests.map((r) {
                  return ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person_add)),
                    title: Text(
                      '${r.senderName} wants to manage your reminders',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.red),
                          onPressed: () => CaregiverService.instance
                              .respondToRequest(r.id, accept: false),
                        ),
                        IconButton(
                          icon: const Icon(Icons.check, color: Colors.green),
                          onPressed: () => CaregiverService.instance
                              .respondToRequest(r.id, accept: true),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Text(
              'People who can manage your reminders',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          StreamBuilder<List<CaregiverLink>>(
            stream: CaregiverService.instance.whoHasAccessToMe(),
            builder: (context, snapshot) {
              final links = snapshot.data ?? [];
              if (links.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No one has access yet.'),
                );
              }
              return Column(
                children: links.map((l) {
                  return ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.shield_rounded),
                    ),
                    title: Text(l.senderName),
                    trailing: TextButton(
                      onPressed: () => _revoke(context, l),
                      child: const Text('Revoke'),
                    ),
                  );
                }).toList(),
              );
            },
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Text(
              'People you manage',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          StreamBuilder<List<CaregiverLink>>(
            stream: CaregiverService.instance.myAcceptedRecipients(),
            builder: (context, snapshot) {
              final links = snapshot.data ?? [];
              if (links.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'No accepted recipients yet — send a request above.',
                  ),
                );
              }
              return Column(
                children: [
                  ...links.map((l) {
                    return ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: Text(l.recipientName),
                      subtitle: const Text('You can set reminders for them'),
                    );
                  }),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const CreateCaregiverReminderScreen(),
                          ),
                        ),
                        icon: const Icon(Icons.alarm_add),
                        label: const Text('Create reminder for someone'),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}