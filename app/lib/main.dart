import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'account_screen.dart';
import 'account_workspace.dart';
import 'auth_client.dart';
import 'assistant_screen.dart';
import 'data_screen.dart';
import 'focus_screen.dart';
import 'guest_screen.dart';
import 'guest_store.dart';
import 'music_screen.dart';
import 'poetry_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'io.github.gamossup.shubchik.playback',
      androidNotificationChannelName: 'Воспроизведение музыки',
      androidNotificationOngoing: true,
    );
  } on PlatformException {
    // Other modules remain available if the media service cannot start.
  }
  runApp(const ShubchikApp());
  unawaited(_restoreAuth());
}

Future<void> _restoreAuth() async {
  try {
    await authClient();
  } catch (_) {
    // The account screen can retry initialization while guest mode stays usable.
  }
}

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

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static final _guest = GuestStore();
  static const _widgetChannel = MethodChannel('shubchik/widget');
  late final Timer _accountSyncTimer;
  bool _syncingAccount = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _accountSyncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_syncAccount());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_syncAccount()));
    _widgetChannel.setMethodCallHandler((call) async {
      if (call.method == 'openSection') _openWidgetSection(call.arguments);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _readWidgetLaunch());
  }

  @override
  void dispose() {
    _accountSyncTimer.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _widgetChannel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_syncAccount());
  }

  bool get _canSyncAccount =>
      mounted &&
      ModalRoute.of(context)?.isCurrent == true &&
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
      AccountSync.openWorkspaces == 0;

  Future<void> _syncAccount() async {
    if (!_canSyncAccount || _syncingAccount) return;
    _syncingAccount = true;
    try {
      if (!await const SecureSessionStorage().hasAccessToken()) return;
      final client = await authClient();
      final accountId = client.auth.currentUser?.id;
      if (!_canSyncAccount || accountId == null) return;
      await AccountSync(client, accountId).synchronize(
        GuestStore(fileName: 'account_$accountId.db'),
      );
    } catch (_) {
      // The next foreground tick retries. The account screen shows sync errors.
    } finally {
      _syncingAccount = false;
    }
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
