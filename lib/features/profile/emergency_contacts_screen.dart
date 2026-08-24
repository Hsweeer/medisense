import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:contacts_service/contacts_service.dart' as cs;
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
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
        padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 24.h),
        children: [
          MCard(
            color: AppColors.dangerSoft,
            border: Border.all(color: AppColors.danger.withValues(alpha: .4)),
            child: Row(
              children: [
                Icon(
                  Icons.local_police_rounded,
                  color: AppColors.danger,
                  size: 26.sp,
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Text(
                    '911 is always dialed first in an SOS. The contacts below '
                    'also get a text with your live location and Medical ID.',
                    style: TextStyle(
                      fontSize: 12.5.sp,
                      height: 1.4,
                      color: AppColors.inkSoft,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 16.h),
          for (final c in prov.contacts)
            Padding(
              padding: EdgeInsets.only(bottom: 10.h),
              child: MCard(
                padding: EdgeInsets.all(14.r),
                child: Row(
                  children: [
                    InitialsAvatar(c.name, size: 42.r),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.name,
                            style: TextStyle(
                              fontSize: 14.5.sp,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 2.h),
                          Text(
                            '${c.relation} · ${c.phone}',
                            style: TextStyle(
                              fontSize: 12.sp,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        prov.removeContact(c);
                        showToast(context, '${c.name} removed');
                      },
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        size: 20.sp,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          SizedBox(height: 16.h),
          Row(
            children: [
              Expanded(
                child: PrimaryButton(
                  label: 'Manual add',
                  icon: Icons.edit_note_rounded,
                  onPressed: () => _showAddSheet(context),
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: SecondaryButton(
                  label: 'Import',
                  icon: Icons.contact_page_rounded,
                  onPressed: () => _importFromContacts(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _importFromContacts(BuildContext context) async {
    try {
      final granted = await Permission.contacts.request();
      if (!granted.isGranted) {
        if (context.mounted) {
          showToast(
            context,
            'Contacts permission denied',
            color: AppColors.danger,
          );
        }
        return;
      }

      final contacts = await cs.ContactsService.getContacts();
      if (!context.mounted) return;

      final contact = await showModalBottomSheet<cs.Contact>(
        context: context,
        builder: (_) => ListView(
          children: contacts
              .where((contact) => contact.phones?.isNotEmpty == true)
              .map(
                (contact) => ListTile(
                  title: Text(contact.displayName ?? 'Unknown'),
                  subtitle: Text(contact.phones!.first.value ?? ''),
                  onTap: () => Navigator.pop(context, contact),
                ),
              )
              .toList(),
        ),
      );
      if (contact == null || !context.mounted) return;

      final name = contact.displayName ?? 'Contact';
      final phone = contact.phones?.first.value ?? '';
      if (phone.isEmpty) {
        showToast(
          context,
          'Contact has no phone number',
          color: AppColors.danger,
        );
        return;
      }

      context.read<ProfileProvider>().addContact(
        EmergencyContact(name: name, relation: 'Contact', phone: phone),
      );
      showToast(context, 'Added $name from contacts');
    } catch (e) {
      if (context.mounted) {
        showToast(context, 'Error picking contact', color: AppColors.danger);
      }
    }
  }

  void _showAddSheet(BuildContext context) {
    final name = TextEditingController();
    final relation = TextEditingController();
    final phone = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
      ),
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20.w,
          20.h,
          20.w,
          20.h + MediaQuery.of(sheetCtx).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add emergency contact',
              style: GoogleFonts.sora(
                fontSize: 17.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 4.h),
            Text(
              'They will be texted your location during an SOS.',
              style: TextStyle(fontSize: 12.5.sp, color: AppColors.muted),
            ),
            SizedBox(height: 14.h),
            TextField(
              controller: name,
              textCapitalization: TextCapitalization.words,
              style: TextStyle(fontSize: 15.sp),
              decoration: const InputDecoration(hintText: 'Full name'),
            ),
            SizedBox(height: 10.h),
            TextField(
              controller: relation,
              textCapitalization: TextCapitalization.words,
              style: TextStyle(fontSize: 15.sp),
              decoration: const InputDecoration(
                hintText: 'Relationship (e.g. Spouse, Neighbor)',
              ),
            ),
            SizedBox(height: 10.h),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              style: TextStyle(fontSize: 15.sp),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d\s()\-+]')),
              ],
              decoration: InputDecoration(
                hintText: 'Phone — (555) 000-0000',
                prefixText: '+1  ',
                prefixStyle: TextStyle(
                  color: AppColors.ink,
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SizedBox(height: 16.h),
            PrimaryButton(
              label: 'Save contact',
              onPressed: () {
                final digits = phone.text.replaceAll(RegExp(r'\D'), '');
                if (name.text.trim().isEmpty || digits.length < 10) {
                  showToast(
                    sheetCtx,
                    'Name and a valid 10-digit phone are required',
                    color: AppColors.danger,
                  );
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
