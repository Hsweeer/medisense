import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'features/splash/splash_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/shell/patient_shell.dart';
import 'features/sos/sos_screen.dart';
import 'features/sos/sos_overlay_button.dart';
import 'firebase_options.dart';
import 'providers/auth_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/location_provider.dart';
import 'providers/notification_provider.dart';
import 'providers/password_reset_provider.dart';
import 'providers/profile_provider.dart';
import 'providers/reminder_provider.dart';
import 'providers/sos_provider.dart';
import 'services/notification_service.dart';

// Global key to allow background navigation
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await NotificationService.instance.initialize();
  runApp(const MediSenseApp());
}

@pragma("vm:entry-point")
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: SosOverlayButton(),
    ),
  );
}

class MediSenseApp extends StatelessWidget {
  const MediSenseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(390, 844),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) => MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => LocationProvider()),
          ChangeNotifierProvider(create: (_) => ProfileProvider()),
          ChangeNotifierProvider(create: (_) => PasswordResetProvider()),
          ChangeNotifierProvider(create: (_) => ReminderProvider()),
          ChangeNotifierProvider(
            create: (ctx) =>
                ChatProvider(reminderEngine: ctx.read<ReminderProvider>()),
          ),
          ChangeNotifierProvider(create: (_) => SosProvider()),
          ChangeNotifierProvider(
            create: (ctx) => NotificationProvider(
              reminderProvider: ctx.read<ReminderProvider>(),
            ),
          ),
        ],
        child: MaterialApp(
          title: 'MediSense',
          navigatorKey: navigatorKey,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          builder: (context, child) {
            return SosGlobalListener(
              child: Container(
                color: const Color(0xFF06413A),
                child: child,
              ),
            );
          },
          home: const AuthWrapper(),
        ),
      ),
    );
  }
}

/// A global listener that lives inside the Provider scope to handle SOS signals
class SosGlobalListener extends StatefulWidget {
  final Widget child;
  const SosGlobalListener({super.key, required this.child});

  @override
  State<SosGlobalListener> createState() => _SosGlobalListenerState();
}

class _SosGlobalListenerState extends State<SosGlobalListener> {
  StreamSubscription? _overlaySub;

  @override
  void initState() {
    super.initState();
    // Re-initialize listener to ensure it's fresh
    _initOverlayListener();
  }

  void _initOverlayListener() {
    _overlaySub?.cancel();
    _overlaySub = FlutterOverlayWindow.overlayListener.listen((data) async {
      if (data == "trigger_sos") {
        debugPrint('[SosGlobalListener] SOS Signal Received FROM OVERLAY');
        
        // 1. Force app to foreground
        try {
          const channel = MethodChannel('com.medisense.medisense_app/native_alarm');
          await channel.invokeMethod('bringToForeground');
        } catch (e) {
          debugPrint('Foreground error: $e');
        }

        // 2. Trigger SOS logic in provider
        if (mounted) {
          context.read<SosProvider>().triggerImmediate();
          
          // 3. Clear stack and push SOS screen
          navigatorKey.currentState?.pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const SosScreen()),
            (route) => route.isFirst,
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _overlaySub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SplashScreen();

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SplashScreen();
        }

        final user = snapshot.data;
        final Widget screen = user != null 
            ? const PatientShell(key: ValueKey('home')) 
            : const LoginScreen(key: ValueKey('login'));

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          switchInCurve: Curves.easeIn,
          switchOutCurve: Curves.easeOut,
          child: screen,
        );
      },
    );
  }
}
