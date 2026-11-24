import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:masjid_khalid_app/main.dart';

void main() {
  testWidgets('Course placeholder screen shows its content', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SectionPage(
            title: 'الدورات',
            description: 'الدورات المتاحة والتسجيل فيها',
            icon: Icons.school_outlined,
          ),
        ),
      ),
    );

    expect(find.text('الدورات'), findsOneWidget);
    expect(find.text('الدورات المتاحة والتسجيل فيها'), findsOneWidget);
    expect(find.byIcon(Icons.school_outlined), findsOneWidget);
  });
}
