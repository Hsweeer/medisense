import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../data/mock/mock_data.dart';
import '../../providers/reminder_provider.dart';
import '../nearby/nearby_screen.dart';
import '../profile/emergency_contacts_screen.dart';
import '../reminders/reminders_screen.dart';

/// Home — "what do I need to do right now?"
/// The next-dose card is the hero, everything else sits below it.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final reminders = context.watch<ReminderProvider>();
    final next = reminders.nextDose;
    final firstName = MockData.userName.split(' ').first;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 90),
        children: [
          // Greeting bar
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Good morning, $firstName 👋',
                        style: Theme.of(context).textTheme.headlineSmall),
                    const Text(MockData.userLocationLabel,
                        style:
                            TextStyle(color: AppColors.muted, fontSize: 13)),
                  ],
                ),
              ),
              const InitialsAvatar(MockData.userName),
            ],
          ),
          const SizedBox(height: 16),
          // Universal search → nearby care
          TextField(
            readOnly: true,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const NearbyScreen(showBack: true))),
            decoration: const InputDecoration(
              hintText: 'Search hospitals, pharmacies…',
              prefixIcon: Icon(Icons.search_rounded, color: AppColors.muted),
            ),
          ),
          const SizedBox(height: 16),
          // HERO — next dose card
          GestureDetector(
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RemindersScreen())),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: AppColors.gradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                      color: AppColors.primary.withValues(alpha: .35),
                      blurRadius: 18,
                      offset: const Offset(0, 8)),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.medication_rounded,
                        color: Colors.white, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          next == null ? 'ALL DONE TODAY' : 'NEXT DOSE',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: .8),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          next == null
                              ? 'Great job — streak safe 🔥'
                              : '${next.title} · ${next.time}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700),
                        ),
                        if (next != null)
                          Text(
                            next.dose,
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: .85),
                                fontSize: 12.5),
                          ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      color: Colors.white),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Quick actions 2×2
          Row(children: [
            Expanded(
                child: _QuickTile(
              icon: Icons.local_hospital_rounded,
              label: 'Hospitals near me',
              sub: 'ER open · directions',
              color: AppColors.primary,
              soft: AppColors.soft,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) =>
                      const NearbyScreen(initialType: 1, showBack: true))),
            )),
            const SizedBox(width: 12),
            Expanded(
                child: _QuickTile(
              icon: Icons.local_pharmacy_rounded,
              label: 'Pharmacies near me',
              sub: '2 open 24 hrs',
              color: AppColors.warning,
              soft: AppColors.warningSoft,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) =>
                      const NearbyScreen(initialType: 2, showBack: true))),
            )),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: _QuickTile(
              icon: Icons.alarm_rounded,
              label: 'My reminders',
              sub: '${reminders.reminders.length} active',
              color: AppColors.primary,
              soft: AppColors.soft,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const RemindersScreen())),
            )),
            const SizedBox(width: 12),
            Expanded(
                child: _QuickTile(
              icon: Icons.contact_emergency_rounded,
              label: 'Emergency contacts',
              sub: 'Alerted during SOS',
              color: AppColors.danger,
              soft: AppColors.dangerSoft,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const EmergencyContactsScreen())),
            )),
          ]),
          const SizedBox(height: 20),
          // One AI insight — kept light.
          const SectionHeader('For you'),
          MCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                      color: AppColors.aiSoft,
                      borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.auto_awesome_rounded,
                      color: AppColors.ai, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(MockData.healthTips[1].$1,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Text(MockData.healthTips[1].$2,
                          style: const TextStyle(
                              fontSize: 12.5,
                              height: 1.4,
                              color: AppColors.muted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({
    required this.icon,
    required this.label,
    required this.sub,
    required this.color,
    required this.soft,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String sub;
  final Color color;
  final Color soft;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: soft,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 10),
          Text(label,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(sub,
              style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
        ],
      ),
    );
  }
}
