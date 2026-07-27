import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../data/models/models.dart';
import '../../providers/profile_provider.dart';

/// Manage the people alerted by Emergency SOS. 911 is always included.
class EmergencyContactsScreen extends StatelessWidget {
  const EmergencyContactsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<ProfileProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Emergency contacts')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          MCard(
            color: AppColors.dangerSoft,
            border: Border.all(color: AppColors.danger.withValues(alpha: .4)),
            child: const Row(
              children: [
                Icon(Icons.local_police_rounded,
                    color: AppColors.danger, size: 26),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '911 is always dialed first in an SOS. The contacts below '
                    'also get a text with your live location and Medical ID.',
                    style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: AppColors.inkSoft),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          for (final c in prov.contacts)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: MCard(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    InitialsAvatar(c.name, size: 42),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.name,
                              style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text('${c.relation} · ${c.phone}',
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.muted)),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        prov.removeContact(c);
                        showToast(context, '${c.name} removed');
                      },
                      icon: const Icon(Icons.delete_outline_rounded,
                          size: 20, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 6),
          PrimaryButton(
            label: 'Add emergency contact',
            icon: Icons.person_add_alt_rounded,
            onPressed: () => _showAddSheet(context),
          ),
        ],
      ),
    );
  }

  void _showAddSheet(BuildContext context) {
    final name = TextEditingController();
    final relation = TextEditingController();
    final phone = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, 20 + MediaQuery.of(sheetCtx).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add emergency contact',
                style: GoogleFonts.sora(
                    fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('They will be texted your location during an SOS.',
                style: TextStyle(fontSize: 12.5, color: AppColors.muted)),
            const SizedBox(height: 14),
            TextField(
                controller: name,
                textCapitalization: TextCapitalization.words,
                decoration:
                    const InputDecoration(hintText: 'Full name')),
            const SizedBox(height: 10),
            TextField(
                controller: relation,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                    hintText: 'Relationship (e.g. Spouse, Neighbor)')),
            const SizedBox(height: 10),
            TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d\s()\-+]')),
                ],
                decoration: const InputDecoration(
                    hintText: 'Phone — (555) 000-0000',
                    prefixText: '+1  ',
                    prefixStyle: TextStyle(
                        color: AppColors.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w600))),
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Save contact',
              onPressed: () {
                final digits = phone.text.replaceAll(RegExp(r'\D'), '');
                if (name.text.trim().isEmpty || digits.length < 10) {
                  showToast(sheetCtx,
                      'Name and a valid 10-digit phone are required',
                      color: AppColors.danger);
                  return;
                }
                sheetCtx.read<ProfileProvider>().addContact(
                      EmergencyContact(
                        name: name.text.trim(),
                        relation: relation.text.trim().isEmpty
                            ? 'Contact'
                            : relation.text.trim(),
                        phone: phone.text.trim(),
                      ),
                    );
                Navigator.of(sheetCtx).pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}
