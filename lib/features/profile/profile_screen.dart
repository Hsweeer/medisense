import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../providers/auth_provider.dart';
import '../../providers/profile_provider.dart';
import '../auth/login_screen.dart';
import 'edit_health_profile_sheet.dart';
import 'edit_profile_screen.dart';
import 'emergency_contacts_screen.dart';
import '../notifications/notifications_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<ProfileProvider>();

    if (prov.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final p = prov.profile;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          MCard(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const EditProfileScreen()),
            ),
            child: Row(
              children: [
                InitialsAvatar(p.name, size: 56, imageUrl: p.imageUrl),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.name.isEmpty ? 'Complete your profile' : p.name,
                        style: GoogleFonts.sora(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        firebaseAuthEmail(context),
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.muted,
                        ),
                      ),
                      if (p.dob.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          p.dob,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.muted),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.only(bottom: 10, top: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Health profile',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                GestureDetector(
                  onTap: () => showEditHealthProfileSheet(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.soft,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: .24),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.edit_rounded,
                          size: 15,
                          color: AppColors.primary,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Edit',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          MCard(
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _Vital(label: 'Blood', value: p.bloodType),
                    _Vital(label: 'Height', value: p.heightLabel),
                    _Vital(label: 'Weight', value: '${p.weightLb} lb'),
                    _Vital(
                      label: 'Born',
                      value: p.dob.isEmpty ? '—' : p.dob.split(',').first,
                    ),
                  ],
                ),
                const Divider(height: 24),
                _ChipRow(
                  label: 'Allergies',
                  values: p.allergies,
                  background: AppColors.dangerSoft,
                  foreground: AppColors.danger,
                ),
                const SizedBox(height: 10),
                _ChipRow(
                  label: 'Conditions',
                  values: p.conditions,
                  background: AppColors.warningSoft,
                  foreground: AppColors.warning,
                ),
                const SizedBox(height: 10),
                _ChipRow(
                  label: 'Medications',
                  values: p.medications,
                  background: AppColors.soft,
                  foreground: AppColors.onSoft,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          MCard(
            color: AppColors.aiSoft,
            border: Border.all(color: AppColors.ai.withValues(alpha: .3)),
            child: const Row(
              children: [
                Icon(Icons.auto_awesome_rounded, color: AppColors.ai, size: 22),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'MedAI personalizes every answer using this profile — '
                    'keep it current for sharper guidance.',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: AppColors.inkSoft,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const SectionHeader('Emergency'),
          MCard(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const EmergencyContactsScreen(),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.dangerSoft,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(
                    Icons.contact_emergency_rounded,
                    color: AppColors.danger,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Emergency contacts',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${prov.contacts.length} saved · alerted during SOS',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const SectionHeader('Settings'),
          MCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _SettingTile(
                  icon: Icons.notifications_outlined,
                  label: 'Notifications',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const NotificationsScreen(),
                      ),
                    );
                  },
                ),
                const Divider(height: 1, indent: 56),
                _SettingTile(
                  icon: Icons.lock_outline_rounded,
                  label: 'Privacy & data',
                  onTap: () => showToast(context, 'Privacy settings'),
                ),
                const Divider(height: 1, indent: 56),
                _SettingTile(
                  icon: Icons.help_outline_rounded,
                  label: 'Help & support',
                  onTap: () => showToast(context, 'Support center'),
                ),
                const Divider(height: 1, indent: 56),
                _SettingTile(
                  icon: Icons.logout_rounded,
                  label: 'Sign out',
                  color: AppColors.danger,
                  onTap: () {
                    context.read<AuthProvider>().logout();
                    context.read<ProfileProvider>().refreshForCurrentUser();
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                      (_) => false,
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Small helper so the profile card shows the signed-in email without
/// importing FirebaseAuth directly into every widget below.
String firebaseAuthEmail(BuildContext context) {
  return context.read<AuthProvider>().currentEmail;
}

class _Vital extends StatelessWidget {
  const _Vital({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: GoogleFonts.sora(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.muted),
        ),
      ],
    );
  }
}

class _ChipRow extends StatelessWidget {
  const _ChipRow({
    required this.label,
    required this.values,
    required this.background,
    required this.foreground,
  });

  final String label;
  final List<String> values;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 92,
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              label,
              style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
            ),
          ),
        ),
        Expanded(
          child: values.isEmpty
              ? const Text(
                  'Not set yet',
                  style: TextStyle(fontSize: 12.5, color: AppColors.muted),
                )
              : Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final v in values)
                      MChip(v, background: background, foreground: foreground),
                  ],
                ),
        ),
      ],
    );
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = AppColors.ink,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          icon,
          color: color == AppColors.ink ? AppColors.inkSoft : color,
          size: 22,
        ),
        title: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: AppColors.muted,
          size: 20,
        ),
      ),
    );
  }
}
