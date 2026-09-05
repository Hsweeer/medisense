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
import 'package:firebase_messaging/firebase_messaging.dart';

import 'core/services/loading_overlay_controller.dart';
import 'core/theme/app_theme.dart';
import 'features/splash/splash_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/shell/patient_shell.dart';
import 'features/sos/sos_screen.dart';
import 'features/sos/sos_overlay_button.dart';
import 'firebase_options.dart';
import 'providers/auth_provider.dart';
import 'services/fcm_token_service.dart';
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
      // Initialize FCM token management (register tokens on login)
      await FcmTokenService.instance.initialize();
      // Starts caregiver/SOS watcher if still needed
      CaregiverAlertWatcher.instance.start();
    } catch (e) {
      debugPrint('[Bootstrap] Critical init error: $e');
      Future.delayed(const Duration(seconds: 1), _bootstrap);
      return;
    }

    if (mounted) setState(() => _initialized = true);
    _setupListeners();

    // Setup FCM foreground/background handlers
    try {
      // Foreground messages — show a local notification
      FirebaseMessaging.onMessage.listen((message) {
        debugPrint('[FCM] onMessage: ${message.messageId}');
        NotificationService.instance.showFcmNotification(message);
      });

      // When the user taps a notification and the app is brought to foreground
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        debugPrint('[FCM] onMessageOpenedApp: ${message.messageId}');
        _handleRemoteMessage(message);
      });

      // Cold-start (app launched by tapping a notification)
      FirebaseMessaging.instance.getInitialMessage().then((message) {
        if (message != null) {
          debugPrint('[FCM] getInitialMessage: ${message.messageId}');
          // Delay slightly to allow app bootstrapping
          Future.delayed(const Duration(milliseconds: 300), () => _handleRemoteMessage(message));
        }
      });
    } catch (e) {
      debugPrint('[FCM] setup error: $e');
    }

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

  void _handleRemoteMessage(RemoteMessage? message) {
    try {
      final Map<dynamic, dynamic> data = (message?.data ?? {}) as Map<dynamic, dynamic>;
      final title = message?.notification?.title ?? data['title'] ?? 'MediSense';
      final body = message?.notification?.body ?? data['body'] ?? '';

      // SOS has a dedicated route
      if ((data['type'] == 'sos_alert') || (data['route'] == 'sos') || (data['screen'] == 'sos')) {
        navigatorKey.currentState?.pushNamedAndRemoveUntil('/sos', (r) => false);
        return;
      }

      // Otherwise show a lightweight dialog offering to open the relevant screen.
      final ctx = navigatorKey.currentState?.context;
      if (ctx == null) return;

      showDialog(
        context: ctx,
        builder: (ctx2) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx2).pop(),
              child: const Text('Close'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(ctx2).pop();
                // Try to navigate if route info exists. Wrap in try/catch to avoid crashes
                try {
                  final routeName = data['routeName'] ?? data['screen'] ?? data['route'];
                  final reminderId = data['reminderId'] ?? data['relatedEntityId'];
                  if (routeName == 'reminder' && reminderId != null) {
                    try {
                      navigatorKey.currentState?.pushNamed('/reminders');
                    } catch (_) {
                      // Route may not be registered; ignore
                    }
                  } else if (routeName == 'caregiver_request') {
                    try {
                      navigatorKey.currentState?.pushNamed('/caregiver_requests');
                    } catch (_) {}
                  } else {
                    // fallback: open app home
                    try {
                      navigatorKey.currentState?.pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const PatientShell()),
                        (r) => false,
                      );
                    } catch (_) {}
                  }
                } catch (e) {
                  debugPrint('[FCM] navigation attempt failed: $e');
                }
              },
              child: const Text('View'),
            ),
          ],
        ),
      );
    } catch (e) {
      debugPrint('[FCM] _handleRemoteMessage error: $e');
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
