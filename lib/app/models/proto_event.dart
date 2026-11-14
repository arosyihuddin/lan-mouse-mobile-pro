import 'dart:typed_data';

/// A lan-mouse protocol event received from a controlling desktop,
/// decoded from its wire frame (see lan-mouse-proto). This is the
/// receiving mirror of the send-side models in input_event.dart,
/// pointer_event.dart and keyboard_event.dart.
///
/// The Rust transport always delivers a full 21-byte buffer (the
/// protocol's MAX_EVENT_SIZE); decoders only read the prefix their
/// event type defines.
sealed class ProtoEvent {
  const ProtoEvent();
}

class PointerMotionEvent extends ProtoEvent {
  final double dx;
  final double dy;
  const PointerMotionEvent(this.dx, this.dy);
}

class PointerButtonEvent extends ProtoEvent {
  /// Linux input event code (0x110 left, 0x111 right, ...).
  final int button;
  final bool down;
  const PointerButtonEvent(this.button, this.down);
}

class PointerAxisEvent extends ProtoEvent {
  final int axis;
  final double value;
  const PointerAxisEvent(this.axis, this.value);
}

class PointerAxis120Event extends ProtoEvent {
  final int axis;
  final int value;
  const PointerAxis120Event(this.axis, this.value);
}

class KeyboardKeyEvent extends ProtoEvent {
  /// Linux evdev scancode.
  final int key;
  final bool down;
  const KeyboardKeyEvent(this.key, this.down);
}

class KeyboardModifiersEvent extends ProtoEvent {
  final int depressed;
  final int latched;
  final int locked;
  final int group;
  const KeyboardModifiersEvent(
    this.depressed,
    this.latched,
    this.locked,
    this.group,
  );
}

class PingEvent extends ProtoEvent {
  const PingEvent();
}

class PongEvent extends ProtoEvent {
  final bool alive;
  const PongEvent(this.alive);
}

class EnterEvent extends ProtoEvent {
  /// Position of this device relative to the desktop, as configured
  /// on the desktop: 0 left, 1 right, 2 top, 3 bottom.
  final int position;
  const EnterEvent(this.position);
}

class LeaveEvent extends ProtoEvent {
  final int serial;
  const LeaveEvent(this.serial);
}

class AckEvent extends ProtoEvent {
  final int serial;
  const AckEvent(this.serial);
}

class HelloEvent extends ProtoEvent {
  /// The peer's 8-byte build identification.
  final String commit;
  const HelloEvent(this.commit);
}

/// Decodes one wire frame. Returns null for unknown event types so
/// newer desktops stay forward-compatible (Hello, for instance,
/// arrived after this app's send-side models were written, whose
/// EventType enum has no value for it).
ProtoEvent? decodeProtoEvent(Uint8List frame) {
  if (frame.isEmpty) return null;
  final data = ByteData.sublistView(frame);
  switch (frame[0]) {
    case 0:
      return PointerMotionEvent(
        data.getFloat64(5, Endian.big),
        data.getFloat64(13, Endian.big),
      );
    case 1:
      return PointerButtonEvent(
        data.getUint32(5, Endian.big),
        data.getUint32(9, Endian.big) != 0,
      );
    case 2:
      return PointerAxisEvent(data.getUint8(5), data.getFloat64(6, Endian.big));
    case 3:
      return PointerAxis120Event(
        data.getUint8(1),
        data.getInt32(2, Endian.big),
      );
    case 4:
      return KeyboardKeyEvent(
        data.getUint32(5, Endian.big),
        data.getUint8(9) != 0,
      );
    case 5:
      return KeyboardModifiersEvent(
        data.getUint32(1, Endian.big),
        data.getUint32(5, Endian.big),
        data.getUint32(9, Endian.big),
        data.getUint32(13, Endian.big),
      );
    case 6:
      return const PingEvent();
    case 7:
      return PongEvent(data.getUint8(1) != 0);
    case 8:
      return EnterEvent(data.getUint8(1));
    case 9:
      return LeaveEvent(data.getUint32(1, Endian.big));
    case 10:
      return AckEvent(data.getUint32(1, Endian.big));
    case 11:
      final bytes = frame.sublist(1, 9);
      return HelloEvent(
        String.fromCharCodes(bytes.map((b) => b == 0 ? 0x3f : b)),
      );
    default:
      return null;
  }
}
