import 'package:flutter/material.dart';
import 'package:lan_mouse_mobile/app/i18n/strings.dart';
import 'package:lan_mouse_mobile/app/modules/home/widgets/home_connections.dart';
import 'package:lan_mouse_mobile/app/modules/home/widgets/home_general.dart';

/// Remote mode screen: this device controls a PC — the app's
/// original home content (General + Connections), now behind the
/// "Control a PC" entry on the home screen.
class RemoteModeView extends StatelessWidget {
  const RemoteModeView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        title: Text(
          tr('remoteModeTitle'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
      body: const Padding(
        padding: EdgeInsets.only(left: 20.0, right: 20.0, top: 20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HomeGeneral(),
              SizedBox(height: 40),
              HomeConnections(),
            ],
          ),
        ),
      ),
    );
  }
}
