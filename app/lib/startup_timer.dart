import 'package:flutter/services.dart';

const _channel = MethodChannel('apex/startup');

/// Milliseconds since Android started the app's process (see MainActivity).
/// Null when unknown, or when the process was already running (e.g. started
/// earlier by a background check), since that wouldn't be a real cold start.
Future<int?> msSinceProcessStart() async {
  try {
    final ms = await _channel.invokeMethod<int>('msSinceProcessStart');
    if (ms == null || ms > 15000) return null;
    return ms;
  } on MissingPluginException {
    return null; // Tests and non-Android platforms.
  } on PlatformException {
    return null;
  }
}
