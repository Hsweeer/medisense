import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/services/caregiver_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/shared_widgets.dart';
import '../../../data/models/caregiver_models.dart';
import 'add_caregiver_screen.dart';
import 'create_caregiver_reminder_screen.dart';

/// "Caregiver requests" — a premium hero header, three color-coded summary
/// cards (pending / who manages you / who you manage), and an "Invite
/// caregiver" call-to-action card. Tapping a summary card opens a detail
/// sheet with the same accept/decline/revoke actions as before — no
/// functionality changed, only the visual layer.
class CaregiverRequestsScreen extends StatelessWidget {
  const CaregiverRequestsScreen({super.key});

  Future<void> _revoke(BuildContext context, CaregiverLink link) async {
    final cancelExisting = await AppDialog.confirm(
      context: context,
      title: 'Restrict ${link.senderName}?',
      message:
          '${link.senderName} won\'t be able to create new reminders for you. '
          'Do you also want to cancel reminders they already created?',
      confirmText: 'Cancel those too',
      cancelText: 'Keep existing reminders',
      destructive: true,
      icon: Icons.block_rounded,
    );
    if (!cancelExisting) return;

    await CaregiverService.instance.revokeAccess(link.id);
    await CaregiverService.instance.cancelRemindersFrom(link.senderUid);
  }

  void _openAddCaregiver(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AddCaregiverScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        elevation: 0,
        title: const Text('Caregiver requests'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Material(
              color: AppColors.soft,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _openAddCaregiver(context),
                child: const Padding(
                  padding: EdgeInsets.all(9),
                  child: Icon(
                    Icons.person_add_alt_1_rounded,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          _HeroHeader(),
          const SizedBox(height: 22),
          StreamBuilder<List<CaregiverLink>>(
            stream: CaregiverService.instance.incomingRequests(),
            builder: (context, snapshot) {
              final requests = snapshot.data ?? [];
              return _SummaryCard(
                icon: Icons.hourglass_top_rounded,
                color: AppColors.warning,
                soft: AppColors.warningSoft,
                title: 'Pending requests',
                subtitle: requests.isEmpty
                    ? 'No pending requests.'
                    : '${requests.length} pending request${requests.length == 1 ? '' : 's'}',
                onTap: () => _openPendingSheet(context, requests),
              );
            },
          ),
          const SizedBox(height: 12),
          StreamBuilder<List<CaregiverLink>>(
            stream: CaregiverService.instance.whoHasAccessToMe(),
            builder: (context, snapshot) {
              final links = snapshot.data ?? [];
              return _SummaryCard(
                icon: Icons.groups_2_rounded,
                color: AppColors.success,
                soft: AppColors.successSoft,
                title: 'People who can manage\nyour reminders',
                subtitle: links.isEmpty
                    ? 'No one has access yet.'
                    : '${links.length} ${links.length == 1 ? 'person has' : 'people have'} access',
                onTap: () => _openAccessSheet(context, links),
              );
            },
          ),
          const SizedBox(height: 12),
          StreamBuilder<List<CaregiverLink>>(
            stream: CaregiverService.instance.myAcceptedRecipients(),
            builder: (context, snapshot) {
              final links = snapshot.data ?? [];
              return _SummaryCard(
                icon: Icons.supervisor_account_rounded,
                color: AppColors.ai,
                soft: AppColors.aiSoft,
                title: 'People you manage',
                subtitle: links.isEmpty
                    ? 'No accepted recipients yet — send a request above.'
                    : '${links.length} ${links.length == 1 ? 'person' : 'people'} you manage',
                onTap: () => _openManagedSheet(context, links),
              );
            },
          ),
          const SizedBox(height: 28),
          _InviteCaregiverCta(onTap: () => _openAddCaregiver(context)),
        ],
      ),
    );
  }

  void _openPendingSheet(BuildContext context, List<CaregiverLink> requests) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (_) => _DetailSheet(
        icon: Icons.hourglass_top_rounded,
        color: AppColors.warning,
        title: 'Pending requests',
        subtitle: 'People who want to manage your reminders.',
        child: requests.isEmpty
            ? const _EmptyRow('No pending requests.')
            : Column(
                children: requests.map((r) {
                  return _PersonRow(
                    icon: Icons.person_add_alt_1_rounded,
                    color: AppColors.warning,
                    soft: AppColors.warningSoft,
                    title: r.senderName,
                    subtitle: 'Wants to manage your reminders',
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _RoundIconAction(
                          icon: Icons.close_rounded,
                          color: AppColors.danger,
                          background: AppColors.dangerSoft,
                          onTap: () => CaregiverService.instance
                              .respondToRequest(r.id, accept: false),
                        ),
                        const SizedBox(width: 8),
                        _RoundIconAction(
                          icon: Icons.check_rounded,
                          color: AppColors.success,
                          background: AppColors.successSoft,
                          onTap: () => CaregiverService.instance
                              .respondToRequest(r.id, accept: true),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
      ),
    );
  }

  void _openAccessSheet(BuildContext context, List<CaregiverLink> links) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (sheetCtx) => _DetailSheet(
        icon: Icons.groups_2_rounded,
        color: AppColors.success,
        title: 'Who can manage your reminders',
        subtitle: 'They can create reminders for you until you revoke access.',
        child: links.isEmpty
            ? const _EmptyRow('No one has access yet.')
            : Column(
                children: links.map((l) {
                  return _PersonRow(
                    icon: Icons.shield_rounded,
                    color: AppColors.success,
                    soft: AppColors.successSoft,
                    title: l.senderName,
                    subtitle: 'Can create reminders for you',
                    trailing: TextButton(
                      onPressed: () => _revoke(sheetCtx, l),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.danger,
                        textStyle: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      child: const Text('Revoke'),
                    ),
                  );
                }).toList(),
              ),
      ),
    );
  }

  void _openManagedSheet(BuildContext context, List<CaregiverLink> links) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (sheetCtx) => _DetailSheet(
        icon: Icons.supervisor_account_rounded,
        color: AppColors.ai,
        title: 'People you manage',
        subtitle: 'You can create reminders on their behalf.',
        child: Column(
          children: [
            if (links.isEmpty)
              const _EmptyRow(
                'No accepted recipients yet — send a request above.',
              )
            else
              ...links.map((l) {
                return _PersonRow(
                  icon: Icons.person_rounded,
                  color: AppColors.ai,
                  soft: AppColors.aiSoft,
                  title: l.recipientName,
                  subtitle: 'You can set reminders for them',
                );
              }),
            const SizedBox(height: 6),
            PrimaryButton(
              label: 'Create reminder for someone',
              onPressed: links.isEmpty
                  ? null
                  : () {
                      Navigator.of(sheetCtx).pop();
                      Navigator.of(sheetCtx).push(
                        MaterialPageRoute(
                          builder: (_) => const CreateCaregiverReminderScreen(),
                        ),
                      );
                    },
            ),
          ],
        ),
      ),
    );
  }
}

/// Top hero banner — soft gradient card with an icon badge, title, and
/// subtitle, replacing the plain app-bar-only header.
class _HeroHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.soft, AppColors.soft.withValues(alpha: .4)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.primary.withValues(alpha: .12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Caregiver\nrequests',
                  style: GoogleFonts.sora(
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Manage who can help you with your reminders.',
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.4,
                    color: AppColors.inkSoft,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: AppColors.gradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: .3),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(
              Icons.family_restroom_rounded,
              color: Colors.white,
              size: 36,
            ),
          ),
        ],
      ),
    );
  }
}

/// One color-coded summary card on the main screen — icon badge, title,
/// subtitle (live count from the stream), and a chevron that opens the
/// matching detail sheet.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.icon,
    required this.color,
    required this.soft,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final Color soft;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: soft,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: color, size: 23),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.muted,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: soft, shape: BoxShape.circle),
            child: Icon(Icons.chevron_right_rounded, color: color, size: 18),
          ),
        ],
      ),
    );
  }
}

/// Bottom call-to-action card — matches the app's gradient hero language
/// (see the home screen's next-dose card) so it reads as a natural,
/// on-brand invite prompt rather than a bolted-on banner.
class _InviteCaregiverCta extends StatelessWidget {
  const _InviteCaregiverCta({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.line),
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: .04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: AppColors.gradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.person_add_alt_1_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Need help managing reminders?',
            textAlign: TextAlign.center,
            style: GoogleFonts.sora(
              fontSize: 16.5,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Invite a caregiver to help you stay on track and never miss an important reminder.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: PrimaryButton(
              label: 'Invite caregiver',
              icon: Icons.person_add_alt_1_rounded,
              onPressed: onTap,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared premium bottom-sheet shell used by all three detail sheets
/// (pending / who-manages-you / who-you-manage) — same handle + icon
/// header language as the rest of the app's sheets.
class _DetailSheet extends StatelessWidget {
  const _DetailSheet({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: .10),
            blurRadius: 30,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SheetHandle(),
              const SizedBox(height: 18),
              SheetHeader(
                icon: icon,
                color: color,
                title: title,
                subtitle: subtitle,
              ),
              const SizedBox(height: 18),
              Flexible(child: SingleChildScrollView(child: child)),
            ],
          ),
        ),
      ),
    );
  }
}

/// One card-style row inside a detail sheet — icon badge, name, subtitle,
/// and an optional trailing action (accept/decline buttons or a revoke
/// text button), matching the app's other card-row language.
class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.icon,
    required this.color,
    required this.soft,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final Color color;
  final Color soft;
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line.withValues(alpha: .7)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: soft,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Small round icon button used for the accept/decline actions on a
/// pending request row.
class _RoundIconAction extends StatelessWidget {
  const _RoundIconAction({
    required this.icon,
    required this.color,
    required this.background,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: color, size: 18),
        ),
      ),
    );
  }
}

/// Empty-state line shown inside a detail sheet when there's nothing to
/// list yet.
class _EmptyRow extends StatelessWidget {
  const _EmptyRow(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 13, color: AppColors.muted),
      ),
    );
  }
}
