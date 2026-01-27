// Basic widget test for Liveness Detection app.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liveness_detection/main.dart';

void main() {
  testWidgets('App displays home screen', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const LivenessDetectionApp());

    // Verify that the app title is displayed.
    expect(find.text('Liveness Detection'), findsOneWidget);

    // Verify the face icon is present.
    expect(find.byIcon(Icons.face_retouching_natural), findsOneWidget);
  });
}
