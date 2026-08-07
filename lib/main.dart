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
import 'features/sos/emergency_ride_screen.dart';
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
  StreamSubscription? _overlaySub;

  @override
  void initState() {
    super.initState();
    _setupListeners();
    
    // Notify native side that Flutter is ready AFTER the first frame is built
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await _nativeChannel.invokeMethod('flutterReady');
        debugPrint('SOS_DEBUG: Notified native that flutter is ready (Post Frame)');
      } catch (e) {
        debugPrint('SOS_DEBUG: Error notifying native: $e');
      }
    });
  }

  @override
  void dispose() {
    _overlaySub?.cancel();
    super.dispose();
  }

  void _setupListeners() {
    debugPrint('SOS_DEBUG: ROOT _setupListeners started');

    // 1. Handle signals from Overlay
    _overlaySub = FlutterOverlayWindow.overlayListener.listen((event) async {
      debugPrint('SOS_DEBUG: overlayListener received event: $event');
      if (event == "trigger_sos") {
        _handleSosNavigation();
      }
    });

    // 2. Handle signals from Native (MethodChannel)
    _nativeChannel.setMethodCallHandler((call) async {
      debugPrint('SOS_DEBUG: Received native call: ${call.method}');
      if (call.method == "openSosScreen") {
        _handleSosNavigation();
      }
    });
  }

  Future<void> _handleSosNavigation() async {
    debugPrint('SOS_DEBUG: _handleSosNavigation triggered');

    try {
      // 1. Get Navigator State
      var state = navigatorKey.currentState;
      debugPrint('SOS_DEBUG: navigatorKey.currentState is ${state == null ? "NULL" : "attached"}');

      // 2. Retry Logic: If null, wait a tiny bit (handles killed app startup race)
      if (state == null) {
        debugPrint('SOS_DEBUG: Navigator not ready, retrying in 500ms...');
        await Future.delayed(const Duration(milliseconds: 500));
        state = navigatorKey.currentState;
        debugPrint('SOS_DEBUG: Retry result -> ${state == null ? "STILL NULL" : "attached"}');
      }

      if (state != null) {
        // 3. Trigger Provider Logic using Navigator's context (which is below MultiProvider)
        final navContext = state.context;
        debugPrint('SOS_DEBUG: Triggering provider logic via navigator context');
        
        // Ensure SOS data is ready
        navContext.read<SosProvider>().triggerImmediate();

        // 4. Execute Navigation - Clears entire stack for DIRECT access
        debugPrint('SOS_DEBUG: Executing pushNamedAndRemoveUntil(/sos)');
        state.pushNamedAndRemoveUntil('/sos', (route) => false);
      } else {
        debugPrint('SOS_DEBUG: ERROR - navigatorKey never attached!');
      }
    } catch (e, st) {
      debugPrint('SOS_DEBUG: Fatal error in _handleSosNavigation: $e');
      debugPrint('SOS_DEBUG: $st');
    }
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
          navigatorKey: navigatorKey, // THE MASTER KEY
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          routes: {
            '/': (ctx) => const AuthWrapper(),
            '/sos': (ctx) => const EmergencyRideScreen(),
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

        final user = snapshot.data;
        final Widget screen = user != null 
            ? const PatientShell(key: ValueKey('home_shell')) 
            : const LoginScreen(key: ValueKey('login_shell'));

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 600),
          switchInCurve: Curves.easeIn,
          switchOutCurve: Curves.easeOut,
          child: screen,
        );
      },
    );
  }
}
