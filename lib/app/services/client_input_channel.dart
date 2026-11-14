import 'dart:async';

import 'package:flutter/services.dart';

/// Dart-to-Android bridge for client mode: forwards decoded input
/// operations to the Kotlin side, which owns the overlay cursor and
/// the accessibility-based gesture injection.
///
/// Calls are fire-and-forget. If the platform side is missing or the
/// accessibility service is off, the failure is logged once and the
/// event stream keeps flowing.
class ClientInputChannel {
  static const MethodChannel _channel = MethodChannel(
    'lan_mouse_mobile/client_input',
  );

  static bool _warnedMissing = false;

  Future<void> _invoke(String method, [Map<String, dynamic>? args]) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } on MissingPluginException {
      if (!_warnedMissing) {
        _warnedMissing = true;
        print('ClientInputChannel: platform side not implemented yet');
      }
    } on PlatformException catch (e) {
      print('ClientInputChannel.$method failed: $e');
    }
  }

  void move(double dx, double dy) =>
      unawaited(_invoke('move', {'dx': dx, 'dy': dy}));

  void button(int button, bool down) =>
      unawaited(_invoke('button', {'button': button, 'down': down}));

  void scroll(int axis, double value) =>
      unawaited(_invoke('scroll', {'axis': axis, 'value': value}));

  void scrollDiscrete(int axis, int value) =>
      unawaited(_invoke('scrollDiscrete', {'axis': axis, 'value': value}));

  void key(int key, bool down) =>
      unawaited(_invoke('key', {'key': key, 'down': down}));

  void modifiers(int depressed, int latched, int locked, int group) =>
      unawaited(
        _invoke('modifiers', {
          'depressed': depressed,
          'latched': latched,
          'locked': locked,
          'group': group,
        }),
      );

  /// Whether the accessibility service (cursor + gestures) is on.
  Future<bool> isAccessibilityEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('isAccessibilityEnabled') ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  void openAccessibilitySettings() =>
      unawaited(_invoke('openAccessibilitySettings'));

  void openInputMethodSettings() =>
      unawaited(_invoke('openInputMethodSettings'));

  void showInputMethodPicker() => unawaited(_invoke('showInputMethodPicker'));

  /// While listening, hold a low-latency WiFi lock and a partial
  /// wake lock: a dozing WiFi radio buffers packets for hundreds
  /// of milliseconds (the freeze-then-jump cursor), and the CPU
  /// lock keeps the receive path responsive in the background.
  void acquireLocks() => unawaited(_invoke('acquireLocks'));
  void releaseLocks() => unawaited(_invoke('releaseLocks'));
  void clipboardStart() => unawaited(_invoke('clipboardStart'));
  void clipboardStop() => unawaited(_invoke('clipboardStop'));

  /// Foreground service: keeps the listening session alive when
  /// the app leaves the foreground or is swiped from Recents
  /// (see LanMouseForegroundService on the Android side).
  void foregroundStart() => unawaited(_invoke('fgStart'));
  void foregroundStop() => unawaited(_invoke('fgStop'));

  /// Registers the handler for requests coming FROM the Android
  /// side: 'requestLeave', fired when the overlay cursor hits the
  /// edge facing the desktop — the desktop must be told (protocol
  /// Leave) to release its capture; and 'requestStopListening',
  /// fired by the foreground-service notification's Stop action.
  void setRequestHandlers({
    required void Function() onLeave,
    required void Function() onStopListening,
  }) {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'requestLeave':
          onLeave();
        case 'requestStopListening':
          onStopListening();
      }
    });
  }

  void enter(int position) =>
      unawaited(_invoke('enter', {'position': position}));

  void leave() => unawaited(_invoke('leave'));

  void sessionEnded() => unawaited(_invoke('sessionEnded'));
}
