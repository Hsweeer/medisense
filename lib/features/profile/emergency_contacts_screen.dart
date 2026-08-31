import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:contacts_service_plus/contacts_service_plus.dart' as cs;
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../data/models/models.dart';
import '../../providers/profile_provider.dart';

/// Manage the people alerted by Emergency SOS. The user's local emergency
/// services number (country-aware, see EmergencyNumberService) is dialed
/// only when the user explicitly taps "Call Emergency" — never automatically.
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
                    'During an SOS you can call emergency services with one tap. '
                    'The contacts below also get a text with your live location '
                    'and Medical ID.',
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

      final phoneContacts = contacts
          .where((contact) => contact.phones?.isNotEmpty == true)
          .toList();

      final contact = await showModalBottomSheet<cs.Contact>(
        context: context,
        backgroundColor: Colors.transparent,
        elevation: 0,
        isScrollControlled: true,
        builder: (_) => DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          expand: false,
          builder: (sheetCtx, scrollController) => Container(
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28.r)),
              boxShadow: [
                BoxShadow(
                  color: AppColors.ink.withValues(alpha: .10),
                  blurRadius: 30.r,
                  offset: Offset(0, -8.h),
                ),
              ],
            ),
            child: Column(
              children: [
                SizedBox(height: 12.h),
                const SheetHandle(),
                Padding(
                  padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 10.h),
                  child: SheetHeader(
                    icon: Icons.contact_page_rounded,
                    color: AppColors.primary,
                    title: 'Choose a contact',
                    subtitle:
                        '${phoneContacts.length} contacts with a phone number',
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    controller: scrollController,
                    padding: EdgeInsets.fromLTRB(20.w, 4.h, 20.w, 20.h),
                    itemCount: phoneContacts.length,
                    separatorBuilder: (_, _) => SizedBox(height: 8.h),
                    itemBuilder: (_, i) {
                      final c = phoneContacts[i];
                      final name = c.displayName ?? 'Unknown';
                      final phone = c.phones!.first.value ?? '';
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => Navigator.pop(context, c),
                          borderRadius: BorderRadius.circular(16.r),
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 12.w,
                              vertical: 10.h,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.paper,
                              borderRadius: BorderRadius.circular(16.r),
                              border: Border.all(
                                color: AppColors.line.withValues(alpha: .7),
                              ),
                            ),
                            child: Row(
                              children: [
                                InitialsAvatar(name, size: 38.r),
                                SizedBox(width: 12.w),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        style: TextStyle(
                                          fontSize: 14.sp,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      SizedBox(height: 1.h),
                                      Text(
                                        phone,
                                        style: TextStyle(
                                          fontSize: 12.sp,
                                          color: AppColors.muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  size: 18.sp,
                                  color: AppColors.muted,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
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
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (sheetCtx) => Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28.r)),
          boxShadow: [
            BoxShadow(
              color: AppColors.ink.withValues(alpha: .10),
              blurRadius: 30.r,
              offset: Offset(0, -8.h),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20.w,
            12.h,
            20.w,
            20.h + MediaQuery.of(sheetCtx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SheetHandle(),
              SizedBox(height: 18.h),
              SheetHeader(
                icon: Icons.person_add_alt_1_rounded,
                color: AppColors.danger,
                title: 'Add emergency contact',
                subtitle: 'They will be texted your location during an SOS.',
              ),
              SizedBox(height: 18.h),
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
              SizedBox(height: 18.h),
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
      ),
    );
  }
}
