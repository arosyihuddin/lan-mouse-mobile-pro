import 'dart:async';
import 'dart:typed_data';

import 'package:lan_mouse_mobile/app/models/proto_event.dart';
import 'package:lan_mouse_mobile/app/rust/api/lan_mouse_server.dart' as rust;
import 'package:lan_mouse_mobile/app/services/client_input_channel.dart';
import 'package:path_provider/path_provider.dart';

/// Connection state for the UI's status card. [connected] means a
/// desktop session exists but its pointer is currently on the
/// desktop; [active] means the pointer is on this device.
enum ClientStatus { stopped, listening, connected, active }

/// Client mode: this device is CONTROLLED by a desktop running
/// lan-mouse — the reverse of [LanMouseServer]'s remote mode.
///
/// Listens for the desktop's DTLS connection (see the Rust `listen`
/// function), decodes its protocol events, answers the protocol
/// replies (Pong for Ping, Ack for Enter/Leave, a Hello echo), and
/// forwards input operations to the Android side through
/// [ClientInputChannel]. Motion is forwarded immediately, frame by
/// frame: batching it on a timer added visible cursor lag, and the
/// single platform channel preserves ordering on its own.
///
/// Crossing back to the desktop is driven from this side, exactly
/// like upstream: when the overlay cursor hits the edge facing the
/// desktop, the Android side asks for a leave (see
/// [ClientInputChannel.setLeaveRequestHandler]) and this service
/// sends the protocol Leave that makes the desktop release its
/// capture.
class LanMouseClient {
  LanMouseClient._privateConstructor() {
    input.setLeaveRequestHandler(_leaveToDesktop);
  }
  static final LanMouseClient instance = LanMouseClient._privateConstructor();

  static const int defaultPort = 4242;

  final ClientInputChannel input = ClientInputChannel();

  rust.SenderWrapper? _sender;
  StreamSubscription<Uint8List>? _subscription;
  bool _helloReplied = false;

  final StreamController<ClientStatus> _statusController =
      StreamController<ClientStatus>.broadcast();
  ClientStatus _status = ClientStatus.stopped;

  bool get isListening => _subscription != null;

  ClientStatus get status => _status;

  /// Whether the desktop's pointer is currently on this device.
  bool get isActive => _status == ClientStatus.active;

  /// Emits whenever [status] changes; the UI uses it for its card.
  Stream<ClientStatus> get statusStream => _statusController.stream;

  /// This device's DTLS fingerprint (the desktop shows it for
  /// verification when it first connects). Same certificate as
  /// remote mode, so the fingerprint is identical in both modes.
  Future<String?> getFingerprint() async {
    final tempDir = await getTemporaryDirectory();
    return rust.getFingerprint(path: tempDir.path);
  }

  void _setStatus(ClientStatus value) {
    if (_status == value) return;
    _status = value;
    _statusController.add(value);
  }

  Future<void> start({
    int port = defaultPort,
    required void Function(String) onError,
  }) async {
    if (isListening) return;
    _helloReplied = false;
    final (sender, receiver) = await rust.createU8Channel();
    _sender = sender;
    final tempDir = await getTemporaryDirectory();
    final stream = rust.listen(
      basePath: tempDir.path,
      port: port,
      rx: receiver,
    );
    _subscription = stream.listen(
      _onFrame,
      onError: (Object err) {
        _setStatus(ClientStatus.stopped);
        onError(err.toString());
      },
      onDone: () {
        _setStatus(ClientStatus.stopped);
        _subscription = null;
        _sender = null;
      },
    );
    _setStatus(ClientStatus.listening);
    input.acquireLocks();
    input.clipboardStart();
    // Once any desktop session has been seen, the status stays
    // "connected" until listening stops: the desktop holds its
    // session open across crossings, so the status never falls
    // back to "waiting" mid-session.
  }

  Future<void> stop() async {
    input.releaseLocks();
    input.clipboardStop();
    // An empty payload is the stop request for the Rust listener.
    await _sender?.send(data: []);
    await _subscription?.cancel();
    _subscription = null;
    _sender = null;
    _setStatus(ClientStatus.stopped);
    input.sessionEnded();
  }

  /// Sends the protocol Leave that releases the desktop's capture,
  /// after the Android side reported the cursor hitting the exit
  /// edge. The desktop answers with its own Leave (handled in
  /// [_onFrame]); the local cursor is hidden right away.
  void _leaveToDesktop() {
    if (_status != ClientStatus.active) return;
    _sendFrame(const [9, 0, 0, 0, 0]); // Leave(0), as upstream sends
    _setStatus(ClientStatus.connected);
    input.leave();
  }

  void _sendFrame(List<int> frame) {
    _sender?.send(data: frame);
  }

  void _onFrame(Uint8List frame) {
    // Any frame at all proves a desktop session exists — the
    // status becomes "connected" long before the first crossing.
    if (_status == ClientStatus.listening) {
      _setStatus(ClientStatus.connected);
    }
    final event = decodeProtoEvent(frame);
    if (event == null) return;
    switch (event) {
      case PointerMotionEvent(:final dx, :final dy):
        if (dx != 0 || dy != 0) input.move(dx, dy);
      case PointerButtonEvent(:final button, :final down):
        input.button(button, down);
      case PointerAxisEvent(:final axis, :final value):
        input.scroll(axis, value);
      case PointerAxis120Event(:final axis, :final value):
        input.scrollDiscrete(axis, value);
      case KeyboardKeyEvent(:final key, :final down):
        input.key(key, down);
      case KeyboardModifiersEvent(
          :final depressed,
          :final latched,
          :final locked,
          :final group
        ):
        input.modifiers(depressed, latched, locked, group);
      case PingEvent():
        // Pong(alive): input emulation is available.
        _sendFrame(const [7, 1]);
      case PongEvent():
        break;
      case EnterEvent(:final position):
        // Always Ack (upstream repeats Enter until it lands), but
        // enter on the Android side only once per visit — repeats
        // would re-snap the cursor and reset its exit tracking.
        final wasActive = _status == ClientStatus.active;
        _setStatus(ClientStatus.active);
        _sendFrame(const [10, 0, 0, 0, 0]);
        if (!wasActive) input.enter(position);
      case LeaveEvent(:final serial):
        if (_status == ClientStatus.active) {
          _setStatus(ClientStatus.connected);
        }
        _helloReplied = false;
        final s = ByteData(4)..setUint32(0, serial, Endian.big);
        _sendFrame([10, ...s.buffer.asUint8List()]);
        input.leave();
      case AckEvent():
        break;
      case HelloEvent():
        if (!_helloReplied) {
          _helloReplied = true;
          // Echo a Hello with this app's own build id (8 bytes).
          _sendFrame([11, ...'lmmobile'.codeUnits]);
        }
    }
  }
}
