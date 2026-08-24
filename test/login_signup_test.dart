import 'package:beeware_app/screens/login_screen.dart';
import 'package:beeware_app/screens/signup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Login screen renders fields and navigates to sign up', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.text('BEEWARE'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('Login'), findsOneWidget);
    expect(find.text('Dont have an account? '), findsOneWidget);

    await tester.tap(find.text('Sign Up'));
    await tester.pumpAndSettle();

    expect(find.byType(SignupScreen), findsOneWidget);
    expect(find.text('Create an Account'), findsOneWidget);
  });

  testWidgets('Signup screen renders create account form', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SignupScreen()));

    expect(find.text('Create an Account'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(4));
    expect(find.text('Sign Up'), findsOneWidget);
  });
}
