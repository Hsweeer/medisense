import 'dart:async';

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
  Timer? _debounce;

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _onSearchChanged(String query) async {
    _debounce?.cancel();
    // A single matching character should already surface suggestions
    // (searchIndex now stores every prefix, not just whole words), so
    // there's no minimum-length gate anymore — just a short debounce to
    // avoid firing a query on every keystroke while the user is typing.
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _notRegistered = false;
        _searching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _runSearch(query);
    });
  }

  Future<void> _runSearch(String query) async {
    _lastQuery = query;
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
    // Stay on the search screen instead of popping — the sent-requests
    // stream below updates this same list live, so the button for
    // `recipient` flips from "Request" to "Sent" right where the user is
    // looking, instead of them having to reopen the screen to see it.
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
                child: StreamBuilder<List<CaregiverLink>>(
                  stream: CaregiverService.instance.mySentRequests(),
                  builder: (context, snapshot) {
                    // Latest status per recipient uid, from every request
                    // I've ever sent them (pending / accepted / declined /
                    // restricted) — declined/restricted fall through to
                    // "Request" again below since those aren't active.
                    final statusByRecipient = <String, CaregiverLinkStatus>{
                      for (final link
                          in snapshot.data ?? const <CaregiverLink>[])
                        link.recipientUid: link.status,
                    };

                    return ListView.separated(
                      padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 24.h),
                      itemCount: _searchResults.length,
                      separatorBuilder: (_, _) => SizedBox(height: 10.h),
                      itemBuilder: (_, i) {
                        final user = _searchResults[i];
                        final status = statusByRecipient[user.uid];
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
                              _RequestButton(
                                status: status,
                                onTap: () => _confirmAndSend(user),
                              ),
                            ],
                          ),
                        );
                      },
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

/// Right-side action on a search result row. Reflects the live status of
/// any request I've already sent this person:
/// - no request yet, or they declined/I revoked → active "Request" button
/// - request pending → "Sent" pill (grey, clock icon) — still tappable,
///   just surfaces a toast instead of sending a duplicate request
/// - request accepted → "Added" pill (green, check icon) — tappable too,
///   lets the person know they're already connected instead of silently
///   doing nothing.
class _RequestButton extends StatelessWidget {
  const _RequestButton({required this.status, required this.onTap});

  final CaregiverLinkStatus? status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (status == CaregiverLinkStatus.pending) {
      return _Pill(
        label: 'Sent',
        icon: Icons.schedule_rounded,
        background: AppColors.paper,
        foreground: AppColors.muted,
        onTap: () => showToast(
          context,
          'Your request has already been sent',
          color: AppColors.muted,
        ),
      );
    }
    if (status == CaregiverLinkStatus.accepted) {
      return _Pill(
        label: 'Added',
        icon: Icons.check_circle_rounded,
        background: AppColors.successSoft,
        foreground: AppColors.success,
        onTap: () => showToast(
          context,
          'You\'re already connected with this person',
          color: AppColors.success,
        ),
      );
    }
    // declined, restricted, or no request at all — free to (re)send.
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10.r),
        ),
      ),
      onPressed: onTap,
      child: Text(
        'Request',
        style: TextStyle(fontSize: 12.5.sp, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.icon,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(color: foreground.withValues(alpha: .3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14.sp, color: foreground),
            SizedBox(width: 5.w),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5.sp,
                fontWeight: FontWeight.w700,
                color: foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
