import 'package:flutter/material.dart';
import 'package:lan_mouse_mobile/app/i18n/strings.dart';
import 'package:lan_mouse_mobile/app/modules/client/client_mode.dart';

/// Home-screen entry to client mode, where a desktop on the same
/// network controls THIS device (the reverse of the remote mode).
class HomeClientMode extends StatelessWidget {
  const HomeClientMode({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.computer_outlined),
        title: Text(tr('clientModeTitle')),
        subtitle: Text(tr('clientModeSubtitle')),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ClientModeView()),
          );
        },
      ),
    );
  }
}
