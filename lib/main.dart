import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'features/splash/splash_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/shell/patient_shell.dart';
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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await NotificationService.instance.initialize();
  runApp(const MediSenseApp());
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
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          // Dark background matches Splash to hide any possible transition artifacts
          builder: (context, child) => Container(
            color: const Color(0xFF06413A), // Darkest splash color
            child: child,
          ),
          home: const AuthWrapper(),
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
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    // Professional 2.5s splash branding duration
    Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    // 1. Branding Phase
    if (!_ready) return const SplashScreen();

    // 2. Data/Auth Phase - Listen once and switch
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
