import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:masjid_khalid_app/main.dart';
import 'package:masjid_khalid_app/screens/legal_page.dart';

void main() {
  for (final privacy in [true, false]) {
    testWidgets('Bundled legal page is readable offline (privacy=$privacy)', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LegalPage(privacy: privacy, contact: 'إدارة المسجد'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(privacy ? 'سياسة الخصوصية' : 'شروط الاستخدام'),
        findsOneWidget,
      );
      expect(find.textContaining('مسجد خالد بن الوليد'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('إدارة المسجد'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('إدارة المسجد'), findsOneWidget);
    });
  }
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
