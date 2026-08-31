import 'package:contacts_service_plus/contacts_service_plus.dart' as cs;
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/services/caregiver_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/shared_widgets.dart';
import '../../../data/models/caregiver_models.dart';

/// Search-and-invite screen for adding a new caregiver contact, restyled to
/// match the app's theme (Sora headings, teal accents, rounded cards) and
/// with tap-anywhere-to-dismiss-keyboard behavior like the rest of the app.
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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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
    try {
      final results = await CaregiverService.instance.searchUsers(query);
      if (!mounted || _lastQuery != query) return;
      setState(() {
        _searchResults = results;
        _notRegistered = results.isEmpty;
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searchResults = [];
        _notRegistered = false;
        _searching = false;
      });
      showToast(context, 'Search failed: $e', color: AppColors.danger);
    }
  }

  Future<void> _pickFromContacts() async {
    final granted = await Permission.contacts.request();
    if (!granted.isGranted) return;

    final contacts = await cs.ContactsService.getContacts();
    if (!mounted) return;

    final picked = await showModalBottomSheet<cs.Contact>(
      context: context,
      backgroundColor: AppColors.paper,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 10.h),
            Container(
              width: 40.w,
              height: 4.h,
              decoration: BoxDecoration(
                color: AppColors.line,
                borderRadius: BorderRadius.circular(99.r),
              ),
            ),
            SizedBox(height: 14.h),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.w),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Choose a contact',
                  style: GoogleFonts.sora(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ),
            ),
            SizedBox(height: 8.h),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                children: contacts
                    .where((c) => c.phones?.isNotEmpty == true)
                    .map(
                      (c) => ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppColors.soft,
                          child: Icon(
                            Icons.person_rounded,
                            color: AppColors.onSoft,
                          ),
                        ),
                        title: Text(
                          c.displayName ?? 'Unknown',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14.sp,
                          ),
                        ),
                        subtitle: Text(
                          c.phones!.first.value ?? '',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 12.sp,
                          ),
                        ),
                        onTap: () => Navigator.pop(context, c),
                      ),
                    )
                    .toList(),
              ),
            ),
            SizedBox(height: 8.h),
          ],
        ),
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

  Future<void> _showInvite(String name) async {
    final shouldShare = await AppDialog.confirm(
      context: context,
      title: '$name doesn\'t have MediSense yet',
      message: 'Invite them to download the app and try again.',
      confirmText: 'Share invite',
      cancelText: 'Close',
      icon: Icons.share_rounded,
      accentColor: AppColors.primary,
    );

    if (!shouldShare || !mounted) return;
    // Share.share('Get MediSense: https://medisense.app/download');
  }

  Future<void> _confirmAndSend(AppUserSummary recipient) async {
    FocusScope.of(context).unfocus();
    final confirmed = await AppDialog.confirm(
      context: context,
      title: 'Send request to ${recipient.name}?',
      message:
          'They\'ll be able to see and accept a request for you to manage their reminders.',
      confirmText: 'Send request',
      cancelText: 'Cancel',
      icon: Icons.person_add_alt_1_rounded,
      accentColor: AppColors.primary,
    );
    if (!confirmed) return;

    await CaregiverService.instance.sendRequest(recipient);
    if (!mounted) return;
    showToast(
      context,
      'Request sent to ${recipient.name}',
      color: AppColors.primary,
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: AppColors.paper,
        appBar: AppBar(
          backgroundColor: AppColors.paper,
          elevation: 0,
          title: Text(
            'Add caregiver contact',
            style: GoogleFonts.sora(
              fontSize: 17.sp,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 4.h),
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  style: TextStyle(
                    fontSize: 14.5.sp,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search by name, phone, username, or email',
                    hintStyle: TextStyle(
                      fontSize: 13.sp,
                      color: AppColors.muted,
                    ),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: AppColors.muted,
                      size: 22.sp,
                    ),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(
                              Icons.close_rounded,
                              color: AppColors.muted,
                              size: 20.sp,
                            ),
                            onPressed: () {
                              _searchController.clear();
                              _onSearchChanged('');
                            },
                          )
                        : null,
                  ),
                ),
              ),
              SizedBox(height: 10.h),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                child: GestureDetector(
                  onTap: _pickFromContacts,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 14.w,
                      vertical: 12.h,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.soft,
                      borderRadius: BorderRadius.circular(14.r),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 34.r,
                          height: 34.r,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: .14),
                            borderRadius: BorderRadius.circular(10.r),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.contacts_rounded,
                            color: AppColors.primary,
                            size: 18.sp,
                          ),
                        ),
                        SizedBox(width: 12.w),
                        Expanded(
                          child: Text(
                            'Pick from phone contacts',
                            style: TextStyle(
                              fontSize: 13.5.sp,
                              fontWeight: FontWeight.w700,
                              color: AppColors.onSoft,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: AppColors.onSoft,
                          size: 20.sp,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(height: 8.h),
              if (_searching)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20.w),
                  child: LinearProgressIndicator(
                    color: AppColors.primary,
                    backgroundColor: AppColors.line,
                    borderRadius: BorderRadius.circular(99.r),
                  ),
                ),
              if (_notRegistered && !_searching)
                Padding(
                  padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 0),
                  child: Container(
                    padding: EdgeInsets.all(14.r),
                    decoration: BoxDecoration(
                      color: AppColors.warningSoft,
                      borderRadius: BorderRadius.circular(14.r),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          color: AppColors.warning,
                          size: 20.sp,
                        ),
                        SizedBox(width: 10.w),
                        Expanded(
                          child: Text(
                            'No matching MediSense account found.',
                            style: TextStyle(
                              fontSize: 12.5.sp,
                              fontWeight: FontWeight.w600,
                              color: AppColors.warning,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: ListView.separated(
                  padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 24.h),
                  itemCount: _searchResults.length,
                  separatorBuilder: (_, _) => SizedBox(height: 10.h),
                  itemBuilder: (_, i) {
                    final user = _searchResults[i];
                    return Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 14.w,
                        vertical: 10.h,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(16.r),
                        border: Border.all(color: AppColors.line),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 20.r,
                            backgroundColor: AppColors.soft,
                            child: Text(
                              user.name.isNotEmpty
                                  ? user.name[0].toUpperCase()
                                  : '?',
                              style: TextStyle(
                                fontSize: 15.sp,
                                fontWeight: FontWeight.w800,
                                color: AppColors.onSoft,
                              ),
                            ),
                          ),
                          SizedBox(width: 12.w),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  user.name,
                                  style: TextStyle(
                                    fontSize: 14.sp,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.ink,
                                  ),
                                ),
                                SizedBox(height: 2.h),
                                Text(
                                  user.phone.isNotEmpty
                                      ? user.phone
                                      : user.email,
                                  style: TextStyle(
                                    fontSize: 12.sp,
                                    color: AppColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(width: 8.w),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              padding: EdgeInsets.symmetric(
                                horizontal: 16.w,
                                vertical: 10.h,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10.r),
                              ),
                            ),
                            onPressed: () => _confirmAndSend(user),
                            child: Text(
                              'Request',
                              style: TextStyle(
                                fontSize: 12.5.sp,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
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
  }
}
