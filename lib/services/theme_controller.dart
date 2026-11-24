import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local display preference; visitors do not need an account.
final ThemeController themeController = ThemeController();

class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController() : super(ThemeMode.light);

  static const String _storageKey = 'masjid_dark_mode';

  Future<void> load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      value = preferences.getBool(_storageKey) == true
          ? ThemeMode.dark
          : ThemeMode.light;
    } catch (_) {
      // Keep light mode when local settings are unavailable.
    }
  }

  Future<void> setDarkMode(bool enabled) async {
    value = enabled ? ThemeMode.dark : ThemeMode.light;
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(_storageKey, enabled);
    } catch (_) {
      // The visual change still works for the current session.
    }
  }
}
