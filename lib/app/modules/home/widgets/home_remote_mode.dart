import 'package:flutter/material.dart';
import 'package:lan_mouse_mobile/app/i18n/strings.dart';
import 'package:lan_mouse_mobile/app/modules/remote/remote_mode.dart';

class HomeRemoteMode extends StatelessWidget {
  const HomeRemoteMode({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr('remoteSection'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 10),
        Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: const Icon(Icons.desktop_windows),
            title: Text(tr('remoteModeTitle')),
            subtitle: Text(tr('remoteModeSubtitle')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const RemoteModeView(),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
