import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:lan_mouse_mobile/app/i18n/strings.dart';

class HomeTop extends StatelessWidget {
  const HomeTop({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SvgPicture.asset(
          'assets/logo.svg',
          width: 120,
        ),
        SizedBox(height: 20, width: MediaQuery.sizeOf(context).width),
        Text(
          appName,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 10),
        Text(
          tr('tagline'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}
