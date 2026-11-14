import 'package:flutter/material.dart';
import 'package:lan_mouse_mobile/app/i18n/strings.dart';
import 'package:lan_mouse_mobile/app/models/client.dart';
import 'package:lan_mouse_mobile/app/modules/home/widgets/add_client.dart';
import 'package:lan_mouse_mobile/app/modules/server/server.dart';
import 'package:lan_mouse_mobile/app/services/lan_mouse_server.dart';
import 'package:lan_mouse_mobile/app/services/storage_service.dart';

class HomeConnections extends StatefulWidget {
  const HomeConnections({super.key});

  @override
  State<HomeConnections> createState() => _HomeConnectionsState();
}

class _HomeConnectionsState extends State<HomeConnections> {
  List<Client> clients = [];
  LanMouseServer lanMouseServer = LanMouseServer.instance;
  StorageService storageService = StorageService.instance;

  @override
  void initState() {
    clients = storageService.getClients();
    super.initState();
  }

  void connectClient(Client client) async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Server(client: client),
      ),
    );
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
              tr('connections'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            InkWell(
              onTap: () {
                showDialog(
                  context: context,
                  builder: (_) {
                    return AddClient(onAdd: (client) {
                      storageService.addClient(client);
                      setState(() {
                        clients.add(client);
                      });
                    });
                  },
                );
              },
              child: Row(
                children: [
                  const Icon(Icons.add),
                  Text(
                    tr('add'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ],
              ),
            )
          ],
        ),
        const SizedBox(height: 10),
        Card(
          margin: EdgeInsets.zero,
          child: clients.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(tr('noClients')),
                  ),
                )
              : ListView.separated(
                  itemCount: clients.length,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemBuilder: (BuildContext context, int index) {
                    Client client = clients[index];
                    return ListTile(
                      leading: const Icon(Icons.desktop_windows),
                      title: Text(client.host),
                      subtitle: Text("${tr('port')}: ${client.port}"),
                      trailing: IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () {
                          storageService.deleteClient(client);
                          setState(() {
                            clients.removeAt(index);
                          });
                        },
                        icon: const Icon(Icons.delete, color: Colors.red),
                      ),
                      onTap: () => connectClient(client),
                    );
                  },
                  separatorBuilder: (context, index) {
                    return const Divider(height: 1);
                  },
                ),
        )
      ],
    );
  }
}
