import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The three looks the app can wear. Night desk is the default.
enum AppStyle { night, paper, bold }

extension AppStyleName on AppStyle {
  String get label => switch (this) {
        AppStyle.night => 'Night desk',
        AppStyle.paper => 'Paper',
        AppStyle.bold => 'Bold',
      };
}

/// How long to keep things on the phone. `null` days = forever.
class Retention {
  final String label;
  final int? days;
  const Retention(this.label, this.days);
}

const textRetentionChoices = [
  Retention('3 months', 90),
  Retention('1 year', 365),
  Retention('Forever', null),
];

const photoRetentionChoices = [
  Retention('7 days', 7),
  Retention('30 days', 30),
  Retention('1 year', 365),
  Retention('Forever', null),
];

/// User settings, stored with shared_preferences.
class Settings extends ChangeNotifier {
  Settings._(this._prefs);

  final SharedPreferences _prefs;

  static Future<Settings> load() async =>
      Settings._(await SharedPreferences.getInstance());

  static const _kStyle = 'style';
  static const _kTheme = 'theme';
  static const _kTextScale = 'text_scale';
  static const _kKeepText = 'keep_text_days';
  static const _kKeepPhotos = 'keep_photo_days';
  static const _kWifiOnly = 'photos_wifi_only';

  AppStyle get style =>
      AppStyle.values.asNameMap()[_prefs.getString(_kStyle)] ?? AppStyle.night;
  set style(AppStyle v) => _set(() => _prefs.setString(_kStyle, v.name));

  ThemeMode get themeMode =>
      ThemeMode.values.asNameMap()[_prefs.getString(_kTheme)] ??
      ThemeMode.system;
  set themeMode(ThemeMode v) => _set(() => _prefs.setString(_kTheme, v.name));

  /// 0.85 to 1.3; 1.0 is normal.
  double get textScale => _prefs.getDouble(_kTextScale) ?? 1.0;
  set textScale(double v) => _set(() => _prefs.setDouble(_kTextScale, v));

  /// Days to keep edition text; null = forever (the default).
  int? get keepTextDays => _readDays(_kKeepText, null);
  set keepTextDays(int? v) => _set(() => _writeDays(_kKeepText, v));

  /// Days to keep photos; null = forever. Default 30.
  int? get keepPhotoDays => _readDays(_kKeepPhotos, 30);
  set keepPhotoDays(int? v) => _set(() => _writeDays(_kKeepPhotos, v));

  bool get photosWifiOnly => _prefs.getBool(_kWifiOnly) ?? false;
  set photosWifiOnly(bool v) => _set(() => _prefs.setBool(_kWifiOnly, v));

  // -1 is stored for "forever" so it differs from "never set".
  int? _readDays(String key, int? fallback) {
    final v = _prefs.getInt(key);
    if (v == null) return fallback;
    return v < 0 ? null : v;
  }

  Future<bool> _writeDays(String key, int? v) => _prefs.setInt(key, v ?? -1);

  void _set(Future<bool> Function() write) {
    write();
    notifyListeners();
  }
}
