import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medisense_app/features/splash/splash_screen.dart';

void main() {
  testWidgets('MediSense boots to splash then login', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: SplashScreen(isSignedIn: () => false)),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('MediSense'), findsOneWidget);
    expect(find.text('Smart care. Anywhere.'), findsOneWidget);

    // Splash auto-advances after ~2.8s; discrete pumps because the
    // breathing/carousel animations never settle.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Your health,\nunderstood.'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });
}
