import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lan_mouse_mobile/app/i18n/strings.dart';
import 'package:lan_mouse_mobile/app/models/client.dart';

class AddClient extends StatefulWidget {
  final Function(Client client) onAdd;
  const AddClient({super.key, required this.onAdd});

  @override
  State<AddClient> createState() => _AddClientState();
}

class _AddClientState extends State<AddClient> {
  var hostController = TextEditingController();
  var portController = TextEditingController();
  var formKey = GlobalKey<FormState>();

  void _onAddTap() {
    if (!formKey.currentState!.validate()) return;
    String host = hostController.text;
    int port = int.parse(portController.text);
    print("Host: $host, Port: $port");
    Navigator.pop(context);
    widget.onAdd(Client(host: host, port: port));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('addClient')),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: hostController,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return tr('enterValidHost');
                }
                // Ensure valid address
                try {
                  InternetAddress(value);
                } catch (e) {
                  return tr('enterValidHost');
                }
                return null;
              },
              decoration: InputDecoration(
                labelText: tr('host'),
              ),
            ),
            TextFormField(
              controller: portController,
              maxLength: 4,
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value == null || value.length != 4) {
                  return tr('enterValidPort');
                }
                return null;
              },
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
              decoration: InputDecoration(
                labelText: tr('port'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
          },
          child: Text(tr('cancel')),
        ),
        TextButton(
          onPressed: _onAddTap,
          child: Text(tr('add')),
        ),
      ],
    );
  }
}
