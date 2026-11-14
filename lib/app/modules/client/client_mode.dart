import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lan_mouse_mobile/app/i18n/strings.dart';
import 'package:lan_mouse_mobile/app/services/client_input_channel.dart';
import 'package:lan_mouse_mobile/app/services/lan_mouse_client.dart';
import 'package:network_info_plus/network_info_plus.dart';

/// Client mode screen: this device is controlled by a desktop
/// running lan-mouse. Starts/stops the listener and walks through
/// the one-time setup (accessibility service for the pointer,
/// Lan Mouse Pro keyboard for typing). The device-info card mirrors
/// the General card of remote mode.
class ClientModeView extends StatefulWidget {
  const ClientModeView({super.key});

  @override
  State<ClientModeView> createState() => _ClientModeViewState();
}

class _ClientModeViewState extends State<ClientModeView>
    with WidgetsBindingObserver {
  final LanMouseClient _client = LanMouseClient.instance;
  final ClientInputChannel _input = ClientInputChannel();

  ClientStatus _status = ClientStatus.stopped;
  StreamSubscription<ClientStatus>? _statusSub;
  Timer? _pollTimer;
  bool _a11yEnabled = false;
  String _ip = '';
  String _fingerprint = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _status = _client.status;
    _statusSub = _client.statusStream.listen((status) {
      if (mounted) setState(() => _status = status);
    });
    // Poll as a safety net so the status card can never go stale.
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _client.status != _status) {
        setState(() => _status = _client.status);
      }
    });
    _loadInfo();
    _refreshA11y();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _statusSub?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshA11y();
      _loadInfo();
    }
  }

  Future<void> _loadInfo() async {
    String ip = '';
    try {
      ip = (await NetworkInfo().getWifiIP()) ?? '';
    } catch (_) {
      ip = '';
    }
    final fp = await _client.getFingerprint();
    if (!mounted) return;
    setState(() {
      _ip = ip;
      _fingerprint = fp ?? '';
    });
  }

  Future<void> _refreshA11y() async {
    final enabled = await _input.isAccessibilityEnabled();
    if (mounted) setState(() => _a11yEnabled = enabled);
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _copy(String value, String label) {
    Clipboard.setData(ClipboardData(text: value));
    _showError(tr('copiedToClipboard').replaceAll('{label}', label));
  }

  Future<void> _toggleListening() async {
    if (_client.isListening) {
      await _client.stop();
    } else {
      // The pointer lives in the accessibility service: without
      // it a listening session would accept the desktop's frames
      // but show nothing. Refuse to start and say why.
      final a11y = await _input.isAccessibilityEnabled();
      if (!mounted) return;
      setState(() => _a11yEnabled = a11y);
      if (!a11y) {
        _showA11yRequired();
        return;
      }
      await _client.start(onError: _showError);
    }
    if (mounted) setState(() => _status = _client.status);
  }

  void _showA11yRequired() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tr('a11yRequired')),
        action: SnackBarAction(
          label: tr('openSettings'),
          onPressed: () => _input.openAccessibilitySettings(),
        ),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  String get _statusText => switch (_status) {
        ClientStatus.active => tr('statusActive'),
        ClientStatus.connected => tr('statusConnected'),
        ClientStatus.listening => tr('statusListening').replaceAll(
            '{port}',
            '${LanMouseClient.defaultPort}',
          ),
        ClientStatus.stopped => tr('statusStopped'),
      };

  IconData get _statusIcon => switch (_status) {
        ClientStatus.active => Icons.mouse,
        ClientStatus.connected => Icons.desktop_windows,
        ClientStatus.listening => Icons.hearing,
        ClientStatus.stopped => Icons.hearing_disabled,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        title: Text(
          tr('clientModeTitle'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.only(left: 20.0, right: 20.0, top: 20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: Icon(_statusIcon),
                  title: Text(_statusText),
                  subtitle: Text(tr('statusCardSubtitle')),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _toggleListening,
                  icon: Icon(
                    _status == ClientStatus.stopped
                        ? Icons.play_arrow
                        : Icons.stop,
                  ),
                  label: Text(
                    _status == ClientStatus.stopped
                        ? tr('startListening')
                        : tr('stopListening'),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    tr('thisDevice'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  IconButton(
                    onPressed: _loadInfo,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              Card(
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.numbers),
                      title: Text(tr('port')),
                      subtitle: Text('${LanMouseClient.defaultPort} (UDP)'),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.wifi),
                      title: Text(tr('hostname')),
                      subtitle: Text(_ip.isEmpty ? '...' : _ip),
                      trailing: const Icon(Icons.copy),
                      onTap: () => _copy(_ip, 'Hostname'),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.fingerprint),
                      title: Text(tr('certFingerprint')),
                      subtitle: Text(
                        _fingerprint,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      trailing: const Icon(Icons.copy),
                      onTap: () => _copy(_fingerprint, 'Fingerprint'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                tr('setup'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Card(
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(
                        _a11yEnabled
                            ? Icons.check_circle
                            : Icons.accessibility_new,
                        color: _a11yEnabled ? Colors.green : null,
                      ),
                      title: Text(tr('a11yTitle')),
                      subtitle: Text(
                        _a11yEnabled ? tr('a11yOn') : tr('a11yOff'),
                      ),
                      trailing:
                          _a11yEnabled ? null : const Icon(Icons.open_in_new),
                      onTap: _a11yEnabled
                          ? null
                          : () => _input.openAccessibilitySettings(),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.keyboard),
                      title: Text(tr('keyboardTitle')),
                      subtitle: Text(tr('keyboardSubtitle')),
                      trailing: const Icon(Icons.expand_more),
                      onTap: () => _input.showInputMethodPicker(),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.settings),
                      title: Text(tr('androidKbSettings')),
                      subtitle: Text(tr('androidKbSettingsSub')),
                      trailing: const Icon(Icons.open_in_new),
                      onTap: () => _input.openInputMethodSettings(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                tr('onDesktop'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(tr('desktopSteps')),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
