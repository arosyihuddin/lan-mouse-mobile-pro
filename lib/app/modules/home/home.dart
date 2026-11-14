import 'package:flutter/material.dart';
import 'package:lan_mouse_mobile/app/i18n/strings.dart';
import 'package:lan_mouse_mobile/app/modules/home/widgets/home_client_mode.dart';
import 'package:lan_mouse_mobile/app/modules/home/widgets/home_remote_mode.dart';
import 'package:lan_mouse_mobile/app/modules/home/widgets/home_top.dart';

class HomeView extends StatelessWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          appName,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        elevation: 0,
        centerTitle: true,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.language),
            onSelected: (code) => LocaleController.instance.setLanguage(code),
            itemBuilder: (context) {
              final current = LocaleController.instance.locale.languageCode;
              return [
                CheckedPopupMenuItem(
                  value: 'id',
                  checked: current == 'id',
                  child: const Text('Bahasa Indonesia'),
                ),
                CheckedPopupMenuItem(
                  value: 'en',
                  checked: current == 'en',
                  child: const Text('English'),
                ),
              ];
            },
          ),
        ],
      ),
      body: const Padding(
        padding: EdgeInsets.only(left: 20.0, right: 20.0, top: 20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HomeTop(),
              SizedBox(height: 40),
              HomeClientMode(),
              SizedBox(height: 16),
              HomeRemoteMode(),
            ],
          ),
        ),
      ),
    );
  }
}
