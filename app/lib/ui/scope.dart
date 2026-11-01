import 'package:flutter/widgets.dart';

import '../app_controller.dart';

/// Makes the [AppController] available to every screen and rebuilds them
/// when it changes.
class AppScope extends InheritedNotifier<AppController> {
  const AppScope({super.key, required AppController app, required super.child})
      : super(notifier: app);

  static AppController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
