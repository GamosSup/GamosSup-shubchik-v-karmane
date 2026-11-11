import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'account_screen.dart';
import 'assistant_screen.dart';
import 'data_screen.dart';
import 'focus_screen.dart';
import 'guest_screen.dart';
import 'guest_store.dart';
import 'music_screen.dart';
import 'poetry_screen.dart';

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

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static final _guest = GuestStore();
  static const _widgetChannel = MethodChannel('shubchik/widget');

  @override
  void initState() {
    super.initState();
    _widgetChannel.setMethodCallHandler((call) async {
      if (call.method == 'openSection') _openWidgetSection(call.arguments);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _readWidgetLaunch());
  }

  @override
  void dispose() {
    _widgetChannel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<void> _readWidgetLaunch() async {
    try {
      _openWidgetSection(await _widgetChannel.invokeMethod<String>('getInitialSection'));
    } on MissingPluginException {
      // The home-screen widget is available on Android builds.
    }
  }

  void _openWidgetSection(Object? section) {
    if (!mounted) return;
    if (section == 'planner') _open(context, finance: false);
    if (section == 'focus') {
      Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => FocusScreen(scope: _guest.fileName),
      ));
    }
  }

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
          ListTile(
            leading: const Icon(Icons.assistant_outlined), title: const Text('Помощник'),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => AssistantScreen(store: _guest)),
            ),
          ),
          ListTile(title: const Text('Аккаунт'), leading: const Icon(Icons.person), onTap: () => Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => AccountScreen(guest: _guest)))),
          ListTile(title: const Text('Мои данные'), leading: const Icon(Icons.backup), onTap: () => Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => DataScreen(store: _guest)))),
          Text('Гостевой режим · данные на телефоне', style: Theme.of(context).textTheme.titleLarge),
          ListTile(
            leading: const Icon(Icons.music_note), title: const Text('Музыка'),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const MusicScreen()),
            ),
          ),
          ListTile(leading: const Icon(Icons.wallet), title: const Text('Финансы'), onTap: () => _open(context, finance: true)),
          ListTile(leading: const Icon(Icons.event), title: const Text('Планировщик'), onTap: () => _open(context, finance: false)),
          ListTile(
            leading: const Icon(Icons.timer_outlined), title: const Text('Pomodoro'),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => FocusScreen(scope: _guest.fileName)),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.school), title: const Text('Развитие'),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const PoetryScreen()),
            ),
          ),
        ],
      ),
    );
  }
}
