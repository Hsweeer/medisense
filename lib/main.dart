import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
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

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
bool gPendingSosNavigation = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
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
    // Wait for the first frame so the platform view/engine is fully
    // attached before making any platform channel calls (Firebase,
    // notifications, native handshake). Calling these synchronously in
    // initState() races with engine attachment and can throw
    // PlatformException(channel-error, Unable to establish connection...).
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    // Critical path: this must complete so the splash screen can go away.
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      await NotificationService.instance.initialize();
    } catch (e) {
      debugPrint('[Bootstrap] Critical init error: $e');
      // Retry ONLY the critical path, not the whole app.
      Future.delayed(const Duration(seconds: 1), _bootstrap);
      return;
    }

    if (mounted) setState(() => _initialized = true);
    _setupListeners();

    // Non-critical native handshake: give the platform view a frame to
    // finish attaching before talking to it, and never let a failure here
    // re-run Firebase/Notification init or block the splash screen.
    WidgetsBinding.instance.addPostFrameCallback((_) => _notifyNativeReady());
  }

  Future<void> _notifyNativeReady({int attempt = 0}) async {
    try {
      await _nativeChannel.invokeMethod('flutterReady');
    } catch (e) {
      debugPrint('[Bootstrap] flutterReady handshake error (attempt $attempt): $e');
      if (attempt < 5) {
        Future.delayed(const Duration(seconds: 1),
                () => _notifyNativeReady(attempt: attempt + 1));
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
      if (call.method == "openSosScreen") {
        _handleSosNavigation();
      } else if (call.method == "stopAlarm") {
        // If the app is open and the user clicks 'Take' on a notification,
        // we can handle it here if needed.
      }
    });
  }

  void _handleSosNavigation() {
    gPendingSosNavigation = true;
    final state = navigatorKey.currentState;
    if (state != null) {
      state.context.read<SosProvider>().triggerImmediate();
      state.pushNamedAndRemoveUntil('/sos', (route) => false);
      gPendingSosNavigation = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // ScreenUtilInit must be at the very top of the build tree
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
          // Use a simple ternary to show splash while initializing
          home: _initialized ? const AuthWrapper() : const SplashScreen(),
          routes: {
            '/sos': (ctx) => const SosScreen(),
          },
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

  @override
  void initState() {
    super.initState();
    Timer(const Duration(milliseconds: 2000), () {
      if (mounted) setState(() => _splashVisible = false);
      if (gPendingSosNavigation) {
        gPendingSosNavigation = false;
        context.read<SosProvider>().triggerImmediate();
        navigatorKey.currentState?.pushNamedAndRemoveUntil('/sos', (route) => false);
      }
    });
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
        return snapshot.hasData ? const PatientShell() : const LoginScreen();
      },
    );
  }
}