import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../data/mock/mock_data.dart';
import '../../providers/profile_provider.dart';
import '../../providers/sos_provider.dart';
import '../profile/emergency_contacts_screen.dart';
import 'emergency_ride_screen.dart';

/// Emergency SOS — 5-second cancel countdown, then the Khidma-style
/// emergency screen: call buttons that work without data, nearest ER
/// selection, and a direct emergency-ride booking. ≤3 taps to a ride.
class SosScreen extends StatelessWidget {
  const SosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sos = context.watch<SosProvider>();
    if (sos.phase == SosPhase.countdown) return const _CountdownView();
    return const _ActiveSosView();
  }
}

// ── Phase 1 · dark countdown ────────────────────────────────────────────

class _CountdownView extends StatelessWidget {
  const _CountdownView();

  @override
  Widget build(BuildContext context) {
    final sos = context.watch<SosProvider>();
    return Scaffold(
      backgroundColor: const Color(0xFF2A0F0D),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('Emergency SOS'),
        titleTextStyle: GoogleFonts.sora(
            fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () {
            context.read<SosProvider>().cancel();
            Navigator.of(context).pop();
          },
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              Text('Sending alert in',
                  style: TextStyle(
                      fontSize: 16,
                      color: Colors.white.withValues(alpha: .8))),
              const SizedBox(height: 18),
              Container(
                width: 168,
                height: 168,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.danger,
                  boxShadow: [
                    BoxShadow(
                        color: AppColors.danger.withValues(alpha: .55),
                        blurRadius: 60,
                        spreadRadius: 8),
                  ],
                ),
                alignment: Alignment.center,
                child: Text('${sos.countdown}',
                    style: GoogleFonts.sora(
                        fontSize: 72,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
              ),
              const SizedBox(height: 26),
              Text(
                  '911 + your emergency contacts will be alerted\nwith your live location',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: Colors.white.withValues(alpha: .75))),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    context.read<SosProvider>().cancel();
                    Navigator.of(context).pop();
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white, width: 1.4),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text("I'M SAFE — CANCEL",
                      style: TextStyle(
                          fontWeight: FontWeight.w700, letterSpacing: 1)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Phase 2 · active SOS (old Khidma layout) ────────────────────────────

class _ActiveSosView extends StatelessWidget {
  const _ActiveSosView();

  @override
  Widget build(BuildContext context) {
    final sos = context.watch<SosProvider>();
    final profile = context.watch<ProfileProvider>();
    final p = profile.profile;
    final contactNames =
        profile.contacts.map((c) => c.name.split(' ').first).join(' · ');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency'),
        backgroundColor: AppColors.dangerSoft,
      ),
      backgroundColor: const Color(0xFFFFF7F6),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [AppColors.danger, Color(0xFFE0554B)]),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              children: [
                Icon(Icons.gps_fixed_rounded, color: Colors.white),
                SizedBox(width: 12),
                Expanded(
                  child: Text('SOS ACTIVE · location locked ✔',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          letterSpacing: .3)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Native-dial buttons — always on top, work with zero data.
          PrimaryButton(
            label: 'CALL 911',
            icon: Icons.call_rounded,
            color: AppColors.ink,
            subLabel: 'works without data',
            onPressed: () => launchUrl(Uri.parse('tel:911')),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () => launchUrl(Uri.parse('tel:18002221222')),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 15),
              side: const BorderSide(color: AppColors.ink, width: 1.3),
              foregroundColor: AppColors.ink,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Poison Control · 1-800-222-1222',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 20),
          const Text('NEAREST HOSPITALS · ER OPEN',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: AppColors.muted)),
          const SizedBox(height: 10),
          for (final h in MockData.hospitals)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: MCard(
                onTap: () => context.read<SosProvider>().selectHospital(h),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                border: sos.selectedHospital == h
                    ? Border.all(color: AppColors.danger, width: 1.5)
                    : null,
                child: Row(
                  children: [
                    Icon(
                      sos.selectedHospital == h
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_off_rounded,
                      color: sos.selectedHospital == h
                          ? AppColors.danger
                          : AppColors.line,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(h.name,
                              style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700)),
                          Text(
                              '${h.distanceMiles} mi · ETA ${h.etaMinutes} min',
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.muted)),
                        ],
                      ),
                    ),
                    const Icon(Icons.navigation_rounded,
                        size: 18, color: AppColors.muted),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 10),
          PrimaryButton(
            label: 'BOOK EMERGENCY RIDE',
            icon: Icons.emergency_share_rounded,
            color: AppColors.danger,
            subLabel:
                'to ${sos.selectedHospital.name} · fare settles after the trip',
            onPressed: () {
              context.read<SosProvider>().bookRide();
              Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const EmergencyRideScreen()));
            },
          ),
          const SizedBox(height: 14),
          MCard(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Material(
              color: Colors.transparent,
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: sos.notifyContacts,
                activeThumbColor: AppColors.danger,
                onChanged: (v) =>
                    context.read<SosProvider>().toggleNotifyContacts(v),
                title: const Text('Auto-text emergency contacts',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: Text(
                    contactNames.isEmpty
                        ? 'No contacts yet — add one below'
                        : '$contactNames — live tracking link',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.muted)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Medical ID — the part responders see.
          MCard(
            border: Border.all(color: AppColors.danger.withValues(alpha: .3)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.medical_information_rounded,
                        color: AppColors.danger, size: 20),
                    const SizedBox(width: 8),
                    Text('Medical ID — shared with responders',
                        style: GoogleFonts.sora(
                            fontSize: 13.5, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${p.bloodType} · allergies: ${p.allergies.join(", ")} · '
                  '${p.conditions.join(", ")} · meds: ${p.medications.join(", ")}',
                  style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: AppColors.inkSoft),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: TextButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const EmergencyContactsScreen())),
              icon: const Icon(Icons.person_add_alt_rounded,
                  size: 18, color: AppColors.muted),
              label: const Text('Manage emergency contacts',
                  style: TextStyle(
                      color: AppColors.muted, fontWeight: FontWeight.w600)),
            ),
          ),
          const Center(
            child: Text(
                'If no driver accepts within 90 seconds, a full-screen '
                '911 call prompt opens automatically.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.muted)),
          ),
        ],
      ),
    );
  }
}
