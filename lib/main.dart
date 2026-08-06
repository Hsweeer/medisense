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

// GLOBAL MASTER KEY FOR NAVIGATION
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await NotificationService.instance.initialize();
  
  // STEP 2: REGISTER LISTENER AT ROOT LEVEL (BEFORE RUNAPP)
  debugPrint('SOS_DEBUG: Global setup -> Registering overlayListener');
  FlutterOverlayWindow.overlayListener.listen((event) async {
    debugPrint('SOS_DEBUG: ROOT overlayListener received event: $event');
    if (event == "trigger_sos") {
      debugPrint('SOS_DEBUG: ROOT -> Triggering SOS Sequence');
      
      const native = MethodChannel('medisense_native_channel');
      try {
        await native.invokeMethod('triggerSosNow');
        debugPrint('SOS_DEBUG: ROOT -> triggerSosNow invoked');
      } catch (e) {
        debugPrint('SOS_DEBUG: ROOT -> triggerSosNow ERROR: $e');
      }

      // Navigate if navigator is ready
      navigatorKey.currentState?.pushNamedAndRemoveUntil('/sos', (route) => route.isFirst);
    }
  });
  debugPrint('SOS_DEBUG: Global setup -> overlayListener registered and listening');

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

class MediSenseApp extends StatefulWidget {
  const MediSenseApp({super.key});

  @override
  State<MediSenseApp> createState() => _MediSenseAppState();
}

class _MediSenseAppState extends State<MediSenseApp> {
  static const _nativeChannel = MethodChannel('medisense_native_channel');

  @override
  void initState() {
    super.initState();
    // Handle native callbacks (e.g. from Notification full-screen intent)
    _nativeChannel.setMethodCallHandler((call) async {
      debugPrint('SOS_DEBUG: Main Engine received native call: ${call.method}');
      if (call.method == "openSosScreen") {
        if (mounted) {
          context.read<SosProvider>().triggerImmediate();
        }
        navigatorKey.currentState?.pushNamedAndRemoveUntil('/sos', (route) => route.isFirst);
      }
    });
  }

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
                ChatProvider(
                    reminderEngine: ctx.read<ReminderProvider>(),
                    profileProvider: ctx.read<ProfileProvider>()),
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
          routes: {
            '/': (ctx) => const AuthWrapper(),
            '/sos': (ctx) => const SosScreen(),
          },
          initialRoute: '/',
          builder: (context, child) => Container(
            color: const Color(0xFF06413A),
            child: child,
          ),
        ),
      ),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _showSplash = true;

  @override
  void initState() {
    super.initState();
    // Professional 2.5s splash delay
    Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _showSplash = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // 1. Stay on splash during initial boot or if timer is still running
        if (_showSplash || snapshot.connectionState == ConnectionState.waiting) {
          return const SplashScreen(key: ValueKey('splash_view'));
        }

        // 2. Decide destination based on Firebase user presence
        final Widget destination = snapshot.hasData
            ? const PatientShell(key: ValueKey('home_view'))
            : const LoginScreen(key: ValueKey('login_view'));

        // 3. One smooth cross-fade transition
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 600),
          switchInCurve: Curves.easeIn,
          switchOutCurve: Curves.easeOut,
          child: destination,
        );
      },
    );
  }
}
