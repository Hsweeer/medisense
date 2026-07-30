import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'features/splash/splash_screen.dart';
import 'firebase_options.dart';
import 'providers/auth_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/password_reset_provider.dart';
import 'providers/profile_provider.dart';
import 'providers/reminder_provider.dart';
import 'providers/sos_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MediSenseApp());
}

class MediSenseApp extends StatelessWidget {
  const MediSenseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ProfileProvider()),
        ChangeNotifierProvider(create: (_) => PasswordResetProvider()),
        ChangeNotifierProvider(create: (_) => ReminderProvider()),
        ChangeNotifierProvider(
            create: (ctx) =>
                ChatProvider(reminderEngine: ctx.read<ReminderProvider>())),
        ChangeNotifierProvider(create: (_) => SosProvider()),
      ],
      child: MaterialApp(
        title: 'MediSense',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: const SplashScreen(),
      ),
    );
  }
}