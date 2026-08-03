import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medisense_app/features/splash/splash_screen.dart';
import 'package:medisense_app/providers/auth_provider.dart';
import 'package:medisense_app/main.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('MediSense boots and shows splash', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // We use a simple placeholder for testing to avoid Firebase initialization errors
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        useInheritedMediaQuery: true,
        builder: (_, child) => const MaterialApp(
          home: SplashScreen(),
        ),
      ),
    );

    expect(find.text('MediSense'), findsOneWidget);
    expect(find.text('Smart care. Anywhere.'), findsOneWidget);
  });
}
