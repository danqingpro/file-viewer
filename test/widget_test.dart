// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:notepadpp/app.dart';
import 'package:notepadpp/core/config/app_info.dart';
import 'package:notepadpp/core/config/app_settings.dart';

void main() {
  testWidgets('App boots and renders editor shell', (WidgetTester tester) async {
    await tester.pumpWidget(EditorApp(settings: AppSettings.defaults()));
    await tester.pump();

    expect(find.textContaining(AppInfo.name), findsWidgets);
  });
}
