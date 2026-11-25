import 'package:masjid_khalid_app/services/registration_privacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:masjid_khalid_app/auth/auth_gate.dart';
import 'package:masjid_khalid_app/services/course_notifications_service.dart';
import 'package:masjid_khalid_app/widgets/registration_privacy_actions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('staff views require a server snapshot without pending writes', () {
    for (final cached in [false, true]) {
      for (final pending in [false, true]) {
        expect(
          serverConfirmedStaffData(fromCache: cached, pendingWrites: pending),
          !cached && !pending,
        );
      }
    }
  });

  test(
    'existing installation credential survives the verification update',
    () async {
      final existing = 'a' * 64;
      SharedPreferences.setMockInitialValues({
        'course_installation_key_v1': existing,
      });
      final service = CourseNotificationsService.instance;
      expect(await service.existingDeviceKey(), existing);
      expect(await service.deviceKey(), existing);
    },
  );

  test('only explicitly verified rows render, including during rollout', () {
    const row = {'status': 'accepted'};
    expect(
      RegistrationInbox.fromPage({
        'registrations': [row],
      }).entries,
      isEmpty,
    );
    final page = RegistrationInbox.fromPage({
      'reference': 'abcdef012345',
      'registrations': [
        row,
        {...row, 'deviceVerified': true},
      ],
    });
    expect(page.entries, hasLength(1));
    expect(page.reference, 'abcdef012345');
  });

  for (final action in ['erase', 'verify', 'withdraw']) {
    testWidgets('$action requires staff identity confirmation', (tester) async {
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await confirmStaffRegistrationAction(
                    context,
                    action: action,
                    label: 'تأكيد',
                    name: 'مشارك تجريبي',
                  );
                },
                child: const Text('فتح'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('فتح'));
      await tester.pumpAndSettle();
      final button = find.widgetWithText(FilledButton, 'تأكيد');
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      if (action == 'verify') {
        expect(tester.widget<FilledButton>(button).onPressed, isNull);
        await tester.enterText(find.byType(TextField), 'abcdef012345');
        await tester.pumpAndSettle();
      }
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(result, action == 'verify' ? 'abcdef012345' : '');
    });
  }
}
