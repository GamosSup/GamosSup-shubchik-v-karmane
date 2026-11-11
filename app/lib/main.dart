import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'account_screen.dart';
import 'data_screen.dart';
import 'guest_screen.dart';
import 'guest_store.dart';

void main() => runApp(const ShubchikApp());

class ShubchikApp extends StatelessWidget {
  const ShubchikApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Шубчик в кармане',
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(colorSchemeSeed: Colors.green),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.green,
        brightness: Brightness.dark,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static final _guest = GuestStore();

  void _open(BuildContext context, {required bool finance}) {
    Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => GuestScreen(store: _guest, finance: finance),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Шубчик в кармане')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(title: const Text('Аккаунт'), leading: const Icon(Icons.person), onTap: () => Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => const AccountScreen()))),
          ListTile(title: const Text('Мои данные'), leading: const Icon(Icons.backup), onTap: () => Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => DataScreen(store: _guest)))),
          Text('Гостевой режим · данные на телефоне', style: Theme.of(context).textTheme.titleLarge),
          const ListTile(leading: Icon(Icons.music_note), title: Text('Музыка'), subtitle: Text('В разработке')),
          ListTile(leading: const Icon(Icons.wallet), title: const Text('Финансы'), onTap: () => _open(context, finance: true)),
          ListTile(leading: const Icon(Icons.event), title: const Text('Планировщик'), onTap: () => _open(context, finance: false)),
          const ListTile(leading: Icon(Icons.school), title: Text('Развитие'), subtitle: Text('В разработке')),
        ],
      ),
    );
  }
}
