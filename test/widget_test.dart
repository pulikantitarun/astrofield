import 'package:astrofield/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  void useLandscapeSurface(WidgetTester tester) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(tester.view.reset);
  }

  testWidgets('shows the AstroField dashboard', (tester) async {
    useLandscapeSurface(tester);
    await tester.pumpWidget(const AstroFieldApp());
    await tester.pump(const Duration(milliseconds: 1800));
    await tester.pumpAndSettle();

    expect(find.text('AstroField'), findsOneWidget);
    expect(find.text('Mobile observatory control'), findsOneWidget);
    expect(find.text('SYSTEM'), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  });

  testWidgets('opens the Camera workflow from bottom navigation', (
    tester,
  ) async {
    useLandscapeSurface(tester);
    await tester.pumpWidget(const AstroFieldApp());
    await tester.pump(const Duration(milliseconds: 1800));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('nav-camera')));
    await tester.pumpAndSettle();

    expect(find.text('Main camera'), findsOneWidget);
    expect(find.text('EXPOSURE'), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  });

  testWidgets('shows the complete PHD2 Guiding Assistant workflow', (
    tester,
  ) async {
    useLandscapeSurface(tester);
    await tester.pumpWidget(const AstroFieldApp());
    await tester.pump(const Duration(milliseconds: 1800));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('nav-guide')));
    await tester.pumpAndSettle();

    expect(find.text('PHD2 Guiding'), findsOneWidget);
    expect(find.text('GUIDING ASSISTANT'), findsOneWidget);
    expect(find.text('Run 10 min'), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  });

  testWidgets('shows the dedicated autofocus workspace', (tester) async {
    useLandscapeSurface(tester);
    await tester.pumpWidget(const AstroFieldApp());
    await tester.pump(const Duration(milliseconds: 1800));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('nav-focus')));
    await tester.pumpAndSettle();

    expect(find.text('Autofocus'), findsOneWidget);
    expect(find.text('Run autofocus now'), findsOneWidget);
    expect(find.text('AUTOMATIC RERUNS'), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  });
}
