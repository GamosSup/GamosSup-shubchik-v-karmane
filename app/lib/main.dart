import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Шубчик в кармане')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Разделы в разработке', style: Theme.of(context).textTheme.titleLarge),
          const ListTile(leading: Icon(Icons.music_note), title: Text('Музыка')),
          const ListTile(leading: Icon(Icons.wallet), title: Text('Финансы')),
          const ListTile(leading: Icon(Icons.event), title: Text('Планировщик')),
          const ListTile(leading: Icon(Icons.school), title: Text('Развитие')),
        ],
      ),
    );
  }
}
