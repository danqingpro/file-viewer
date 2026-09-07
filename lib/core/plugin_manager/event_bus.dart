import 'dart:async';

/// A lightweight global event bus used by the kernel to broadcast events
/// (file opened, tab switched, cursor moved, format applied, etc.).
///
/// Plugins and UI layers subscribe to the topics they care about without
/// holding direct references to each other, which keeps the kernel stable
/// and the plugins independent.
class EventBus {
  final Map<String, StreamController<_Event>> _controllers = {};

  /// Subscribe to events of [topic]. Returns a subscription that should be
  /// cancelled when the listener is disposed.
  StreamSubscription<_Event> on(String topic, void Function(_Event event) onEvent) {
    final controller = _controllers.putIfAbsent(topic, () => StreamController<_Event>.broadcast());
    return controller.stream.listen((event) => onEvent(event));
  }

  /// Emit a payload to all subscribers of [topic].
  void emit(String topic, [Map<String, dynamic>? payload]) {
    final controller = _controllers[topic];
    if (controller != null && !controller.isClosed) {
      controller.add(_Event(topic, payload ?? const {}));
    }
  }

  /// Tear down all streams. Called once on application shutdown.
  Future<void> dispose() async {
    for (final c in _controllers.values) {
      await c.close();
    }
    _controllers.clear();
  }
}

/// Immutable event envelope carried by the bus.
class _Event {
  final String topic;
  final Map<String, dynamic> payload;
  const _Event(this.topic, this.payload);
}

/// Well-known event topics used across the app.
abstract final class AppEvents {
  static const String fileOpened = 'file.opened';
  static const String fileSaved = 'file.saved';
  static const String tabSwitched = 'tab.switched';
  static const String tabClosed = 'tab.closed';
  static const String cursorMoved = 'cursor.moved';
  static const String formatApplied = 'format.applied';
  static const String voiceStatus = 'voice.status';
}
