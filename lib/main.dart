import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:lan_mouse_mobile/app/i18n/strings.dart';
import 'package:lan_mouse_mobile/app/rust/frb_generated.dart';
import 'package:lan_mouse_mobile/app/modules/home/home.dart';
import 'package:lan_mouse_mobile/app/services/storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  await StorageService.instance.init();
  await LocaleController.instance.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LocaleController.instance,
      builder: (context, _) {
        return MaterialApp(
          // Remount the whole app when the language changes, so
          // every screen rebuilds in the new language (const
          // subtrees would otherwise keep the old strings).
          key: ValueKey(LocaleController.instance.locale.languageCode),
          debugShowCheckedModeBanner: false,
          locale: LocaleController.instance.locale,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en'), Locale('id')],
          darkTheme: ThemeData.dark().copyWith(
            scaffoldBackgroundColor: const Color(0xff282424),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xff282424),
            ),
            cardTheme: const CardThemeData(
              color: Color(0xff363636),
            ),
          ),
          theme: ThemeData.light().copyWith(
            scaffoldBackgroundColor: const Color(0xfffafafa),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xfffafafa),
            ),
            cardTheme: const CardThemeData(
              color: Color(0xffffffff),
            ),
          ),
          themeMode: ThemeMode.system,
          home: const HomeView(),
        );
      },
    );
  }
}
