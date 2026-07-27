import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/sos_provider.dart';
import '../chat/ai_chat_screen.dart';
import '../home/home_screen.dart';
import '../nearby/nearby_screen.dart';
import '../profile/profile_screen.dart';
import '../reminders/reminders_screen.dart';
import '../sos/sos_screen.dart';

/// Bottom-tab scaffold: home · remind · [SOS] · nearby · profile,
/// plus the floating MedAI button and the 2s long-press SOS trigger.
class PatientShell extends StatefulWidget {
  const PatientShell({super.key});

  @override
  State<PatientShell> createState() => _PatientShellState();
}

class _PatientShellState extends State<PatientShell> {
  int index = 0;

  static const _tabs = [
    HomeScreen(),
    RemindersScreen(),
    NearbyScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _tabs[index],
      floatingActionButton: index == 0
          ? FloatingActionButton.extended(
              heroTag: 'med-ai',
              backgroundColor: AppColors.ai,
              foregroundColor: Colors.white,
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AiChatScreen())),
              icon: const Icon(Icons.psychology_alt_rounded),
              label: const Text('MedAI',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            )
          : null,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: const Border(top: BorderSide(color: AppColors.line)),
          boxShadow: [
            BoxShadow(
                color: AppColors.ink.withValues(alpha: .05), blurRadius: 12),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                _navItem(0, Icons.home_rounded, 'Home'),
                _navItem(1, Icons.alarm_rounded, 'Remind'),
                _sosItem(),
                _navItem(2, Icons.map_rounded, 'Nearby'),
                _navItem(3, Icons.person_rounded, 'Profile'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _navItem(int i, IconData icon, String label) {
    final selected = index == i;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => index = i),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
              decoration: BoxDecoration(
                color: selected ? AppColors.soft : Colors.transparent,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Icon(icon,
                  size: 24,
                  color: selected ? AppColors.primary : AppColors.muted),
            ),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight:
                        selected ? FontWeight.w700 : FontWeight.w500,
                    color:
                        selected ? AppColors.primary : AppColors.muted)),
          ],
        ),
      ),
    );
  }

  /// SOS — a short tap shows a hint; only a 2-second long-press triggers it.
  Widget _sosItem() {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(const SnackBar(
            backgroundColor: AppColors.danger,
            content: Text('Hold for 2 seconds to trigger SOS',
                style: TextStyle(fontWeight: FontWeight.w600)),
          )),
        onLongPress: () {
          context.read<SosProvider>().trigger();
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const SosScreen()));
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [AppColors.danger, Color(0xFFE0554B)]),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: AppColors.danger.withValues(alpha: .4),
                      blurRadius: 10,
                      offset: const Offset(0, 3)),
                ],
              ),
              child: const Icon(Icons.sos_rounded,
                  color: Colors.white, size: 24),
            ),
            const SizedBox(height: 2),
            const Text('Hold 2s',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.danger)),
          ],
        ),
      ),
    );
  }
}
