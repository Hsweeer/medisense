// PATH: lib/main.dart
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show debugPaintBaselinesEnabled;
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

import 'core/services/loading_overlay_controller.dart';
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
import 'services/caregiver_alert_watcher.dart';
import 'services/notification_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
bool gPendingSosNavigation = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Prevent Flutter inspector baseline guides from appearing over app text.
  debugPaintBaselinesEnabled = false;
  await dotenv.load(fileName: ".env");
  // GetX is used only for lightweight, context-free UI control of the
  // premium loading overlay. All business/app state stays in Provider.
  Get.put(LoadingOverlayController(), permanent: true);
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
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      await NotificationService.instance.initialize();
      // Turns caregiver-request and SOS Firestore events into local
      // notifications (see CaregiverAlertWatcher for what it covers).
      // Starts/re-attaches itself per signed-in account.
      CaregiverAlertWatcher.instance.start();
    } catch (e) {
      debugPrint('[Bootstrap] Critical init error: $e');
      Future.delayed(const Duration(seconds: 1), _bootstrap);
      return;
    }

    if (mounted) setState(() => _initialized = true);
    _setupListeners();
    WidgetsBinding.instance.addPostFrameCallback((_) => _notifyNativeReady());
  }

  Future<void> _notifyNativeReady({int attempt = 0}) async {
    try {
      await _nativeChannel.invokeMethod('flutterReady');
    } catch (e) {
      debugPrint(
        '[Bootstrap] flutterReady handshake error (attempt $attempt): $e',
      );
      if (attempt < 5) {
        Future.delayed(
          const Duration(seconds: 1),
          () => _notifyNativeReady(attempt: attempt + 1),
        );
      }
    }
  }

  @override
  void dispose() {
    _overlaySub?.cancel();
    super.dispose();
  }

  void _setupListeners() {
    _overlaySub = FlutterOverlayWindow.overlayListener.listen((event) {
      if (event == "trigger_sos") _handleSosNavigation();
    });

    _nativeChannel.setMethodCallHandler((call) async {
      if (call.method == "openSosScreen") _handleSosNavigation();
    });
  }

  void _handleSosNavigation() {
    debugPrint('SOS_DEBUG: _handleSosNavigation called');
    gPendingSosNavigation = true;
    final state = navigatorKey.currentState;
    if (state != null) {
      try {
        final locProvider = state.context.read<LocationProvider>();
        final profileProvider = state.context.read<ProfileProvider>();
        final sosProvider = state.context.read<SosProvider>();
        sosProvider.triggerImmediate(
          locProvider.position,
          profileProvider.contacts,
        );
        state.pushNamedAndRemoveUntil('/sos', (route) => false);
      } catch (e) {
        debugPrint('SOS_DEBUG: navigation error: $e');
      }
      gPendingSosNavigation = false;
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
            create: (ctx) => ChatProvider(
              reminderEngine: ctx.read<ReminderProvider>(),
              profileProvider: ctx.read<ProfileProvider>(),
            ),
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
          home: _initialized ? const AuthWrapper() : const SplashScreen(),
          routes: {'/sos': (ctx) => const SosScreen()},
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
  bool _splashVisible = true;
  Timer? _splashTimer;

  @override
  void initState() {
    super.initState();
    _splashTimer = Timer(const Duration(milliseconds: 2000), () {
      if (!mounted) return;
      setState(() => _splashVisible = false);
    });
  }

  @override
  void dispose() {
    _splashTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_splashVisible) return const SplashScreen();

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SplashScreen();
        }
        if (snapshot.hasData) return const PatientShell();

        // No real account signed in — either show the login screen, or,
        // if the person tapped "Continue as Guest" there, drop them into
        // the shell in guest mode. PatientShell and every screen under it
        // read AuthProvider.isGuest directly via Provider, so no extra
        // constructor plumbing is needed here. isGuest resets to false
        // automatically the moment a real sign-in succeeds.
        final isGuest = context.watch<AuthProvider>().isGuest;
        return isGuest ? const PatientShell() : const LoginScreen();
      },
    );
  }
}
