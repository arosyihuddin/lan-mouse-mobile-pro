import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lan_mouse_mobile/app/i18n/strings.dart';
import 'package:lan_mouse_mobile/app/services/lan_mouse_server.dart';
import 'package:network_info_plus/network_info_plus.dart';

class HomeGeneral extends StatefulWidget {
  const HomeGeneral({super.key});

  @override
  State<HomeGeneral> createState() => _HomeGeneralState();
}

class _HomeGeneralState extends State<HomeGeneral> {
  LanMouseServer lanMouseServer = LanMouseServer.instance;
  String fingerprint = "";

  var portController = TextEditingController();
  var hostnameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    portController.text = lanMouseServer.defaultClient.port.toString();
    hostnameController.text = lanMouseServer.defaultClient.host;
    _refreshData();
  }

  void _refreshData() async {
    // Load Ip
    try {
      NetworkInfo network = NetworkInfo();
      hostnameController.text = (await network.getWifiIP()) ?? "127.0.0.1";
    } catch (e) {
      showSnackbar("NetworkInfoError: $e");
    }
    // Load FingerPrint
    try {
      String? data = await lanMouseServer.getFingerprint();
      if (data != null) {
        setState(() {
          fingerprint = data;
        });
      } else {
        showSnackbar(tr('failedFingerprint'));
      }
    } catch (e) {
      showSnackbar("${tr('failedFingerprint')}: $e");
    }
    _syncHost();
  }

  void showSnackbar(message) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message.toString())),
      );
    }
  }

  void _syncHost() {
    lanMouseServer.defaultClient.host = hostnameController.text;
    lanMouseServer.defaultClient.port = int.parse(portController.text);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              tr('general'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            IconButton(
              onPressed: _refreshData,
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
                subtitle: TextFormField(
                  controller: portController,
                  maxLength: 4,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: InputDecoration(
                    hintText: tr('port'),
                    border: InputBorder.none,
                    counterText: "",
                    isDense: true,
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.wifi),
                title: Text(tr('hostname')),
                subtitle: TextFormField(
                  controller: hostnameController,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: tr('host'),
                    counterText: "",
                    isDense: true,
                  ),
                ),
                trailing: const Icon(Icons.copy),
                onTap: () {
                  Clipboard.setData(
                    ClipboardData(text: hostnameController.text),
                  );
                  showSnackbar(tr('hostnameCopied'));
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.fingerprint),
                title: Text(tr('certFingerprint')),
                subtitle: Text(
                  fingerprint,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                trailing: const Icon(Icons.copy),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: fingerprint));
                  showSnackbar(tr('fingerprintCopied'));
                },
              ),
            ],
          ),
        )
      ],
    );
  }
}
