import 'package:flutter/material.dart';
import 'package:lan_mouse_mobile/app/rust/frb_generated.dart';
import 'package:lan_mouse_mobile/app/modules/home/home.dart';
import 'package:lan_mouse_mobile/app/services/storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  await StorageService.instance.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      darkTheme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xff202124),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xff202124),
          foregroundColor: Color(0xffF5F5F5),
          toolbarHeight: 56,
        ),
        cardTheme: const CardThemeData(
          color: Color(0xff363636),
          margin: EdgeInsets.zero,
          elevation: 0,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          clipBehavior: Clip.antiAlias,
        ),
        focusColor: const Color(0xff315B86),
        textTheme: ThemeData.dark().textTheme.copyWith(
              titleLarge:
                  const TextStyle(fontSize: 34, fontWeight: FontWeight.w700),
              titleMedium:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              titleSmall:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              bodyLarge: const TextStyle(fontSize: 18),
            ),
      ),
      theme: ThemeData.light().copyWith(
        scaffoldBackgroundColor: const Color(0xfffafafa),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xfffafafa),
        ),
        cardTheme: const CardThemeData(
          color: Color(0xffffffff),
          margin: EdgeInsets.zero,
          elevation: 0,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          clipBehavior: Clip.antiAlias,
        ),
        focusColor: const Color(0xffB8DBFF),
      ),
      themeMode: ThemeMode.dark,
      home: const HomeView(),
    );
  }
}
