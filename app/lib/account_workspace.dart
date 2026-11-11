import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'assistant_screen.dart';
import 'data_screen.dart';
import 'guest_screen.dart';
import 'guest_store.dart';
import 'history_screen.dart';

typedef Snapshot = ({int revision, String payload});
typedef SyncState = ({int revision, String local, String base});

enum SyncDecision { unchanged, download, upload, conflict }

SyncDecision compareSnapshots(SyncState state, Snapshot remote) {
  if (state.local == remote.payload) return SyncDecision.unchanged;
  if (state.local == state.base) return SyncDecision.download;
  if (state.revision == remote.revision && state.base == remote.payload) {
    return SyncDecision.upload;
  }
  return SyncDecision.conflict;
}

class AccountWorkspace extends StatefulWidget {
  const AccountWorkspace({
    super.key, required this.client, required this.accountId, required this.guest,
  });

  final SupabaseClient client;
  final String accountId;
  final GuestStore guest;

  @override
  State<AccountWorkspace> createState() => _AccountWorkspaceState();
}

class _AccountWorkspaceState extends State<AccountWorkspace> with WidgetsBindingObserver {
  late final GuestStore _store = GuestStore(fileName: 'account_${widget.accountId}.db');
  late final Timer _timer;
  late final StreamSubscription<AuthState> _authChanges;
  bool _busy = false;
  bool _editorOpen = false;
  String _status = 'Проверяем синхронизацию…';
  ({SyncState local, Snapshot remote})? _conflict;

  bool get _sameAccount => widget.client.auth.currentUser?.id == widget.accountId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authChanges = widget.client.auth.onAuthStateChange.listen((_) {
      if (!_sameAccount && mounted) setState(() {});
    }, onError: (Object _) {});
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        unawaited(_sync());
      }
    });
    unawaited(_sync());
  }

  @override
  void dispose() {
    _timer.cancel();
    unawaited(_authChanges.cancel());
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_sync());
  }

  Future<Snapshot> _readRemote() async {
    final row = await widget.client.from('account_snapshots')
        .select('revision,payload').eq('owner_id', widget.accountId).maybeSingle();
    if (row == null) return (revision: 0, payload: encodeBackup([], []));
    final decoded = decodeBackup(jsonEncode(row['payload']));
    return (
      revision: row['revision'] as int,
      payload: encodeBackup(decoded.tasks, decoded.ledger),
    );
  }

  Future<int> _push(String payload, int revision) async {
    if (!_sameAccount) throw StateError('Account changed');
    return await widget.client.rpc('save_account_snapshot', params: {
      'expected_revision': revision,
      'backup': jsonDecode(payload),
    }) as int;
  }

  Future<void> _sync() async {
    if (!mounted || _busy || _editorOpen || !_sameAccount) return;
    setState(() => _busy = true);
    try {
      final local = await _store.readSyncState();
      if (!_sameAccount) return;
      final remote = await _readRemote();
      if (!mounted || !_sameAccount) return;
      final decision = compareSnapshots(local, remote);
      if (decision == SyncDecision.conflict) {
        setState(() {
          _conflict = (local: local, remote: remote);
          _status = 'На другом устройстве есть изменения. Выберите версию.';
        });
        return;
      }
      final uploading = decision == SyncDecision.upload;
      final revision = uploading ? await _push(local.local, remote.revision) : remote.revision;
      if (!mounted || !_sameAccount) return;
      final accepted = await _store.acceptSync(
        revision: revision,
        payload: uploading ? local.local : remote.payload,
        expectedLocal: local.local,
        replaceLocal: decision == SyncDecision.download,
      );
      if (mounted) setState(() {
        _conflict = null;
        _status = accepted ? 'Синхронизация выполнена' : 'Есть новые локальные изменения';
      });
    } catch (_) {
      if (mounted) setState(() => _status = 'Синхронизация недоступна. Записи остаются на телефоне.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String message) async => await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title), content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Подтвердить')),
      ],
    ),
  ) ?? false;

  Future<void> _resolve({required bool useRemote}) async {
    final conflict = _conflict;
    if (conflict == null || _busy) return;
    final confirmed = await _confirm(
      useRemote ? 'Взять облачную версию?' : 'Взять версию с телефона?',
      'Изменения из другой версии будут заменены. Сначала можно сохранить локальную копию в разделе «Мои данные».',
    );
    if (!mounted || !confirmed || _busy || !_sameAccount || _conflict != conflict) return;
    setState(() => _busy = true);
    try {
      final current = await _store.readSyncState();
      if (current.local != conflict.local.local) throw StateError('Local changed');
      final payload = useRemote ? conflict.remote.payload : current.local;
      final revision = useRemote ? conflict.remote.revision : await _push(payload, conflict.remote.revision);
      if (!mounted || !_sameAccount) return;
      final accepted = await _store.acceptSync(
        revision: revision, payload: payload, expectedLocal: current.local,
        replaceLocal: useRemote,
      );
      if (!accepted) throw StateError('Local changed');
      if (mounted) setState(() {
        _conflict = null;
        _status = 'Версия выбрана';
      });
    } catch (_) {
      if (mounted) setState(() => _status = 'Версии изменились или сеть недоступна. Повторите синхронизацию.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyGuest() async {
    final confirmed = await _confirm('Скопировать гостевые записи?',
      'Копирование доступно для пустого аккаунта. Гостевые записи останутся на телефоне.');
    if (!mounted || !confirmed || _busy || !_sameAccount) return;
    setState(() => _busy = true);
    try {
      final remote = await _readRemote();
      final local = await _store.readSyncState();
      if (remote.revision != 0 || local.revision != 0) {
        if (mounted) setState(() => _status = 'В аккаунте уже есть облачная версия');
        return;
      }
      final payload = await widget.guest.exportBackup();
      if (!_sameAccount) return;
      final copied = await _store.importIfEmpty(payload);
      if (mounted) setState(() => _status = copied ? 'Гостевые записи скопированы' : 'В аккаунте уже есть записи');
    } catch (_) {
      if (mounted) setState(() => _status = 'Не удалось скопировать записи');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _sync();
  }

  Future<void> _open(Widget page) async {
    if (_busy || _editorOpen || !_sameAccount) return;
    _editorOpen = true;
    try {
      await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => page));
    } finally {
      _editorOpen = false;
    }
    if (mounted) await _sync();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Данные аккаунта')),
    body: !_sameAccount ? const Center(child: Text('Войдите снова')) : ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ListTile(title: const Text('Планировщик'), onTap: _busy ? null : () => _open(GuestScreen(store: _store, finance: false))),
        ListTile(title: const Text('Финансы'), onTap: _busy ? null : () => _open(GuestScreen(store: _store, finance: true))),
        ListTile(
          title: const Text('Помощник'),
          onTap: _busy ? null : () => _open(AssistantScreen(store: _store, accountId: widget.accountId)),
        ),
        ListTile(title: const Text('Мои данные'), onTap: _busy ? null : () => _open(DataScreen(store: _store))),
        ListTile(
          title: const Text('Облачные копии'),
          onTap: _busy ? null : () => _open(HistoryScreen(
            client: widget.client, accountId: widget.accountId, store: _store,
          )),
        ),
        const Divider(),
        Text(_status),
        if (_busy) const LinearProgressIndicator(),
        TextButton(onPressed: _busy ? null : _sync, child: const Text('Синхронизировать')),
        TextButton(onPressed: _busy ? null : _copyGuest, child: const Text('Скопировать гостевые записи')),
        if (_conflict != null) ...[
          OutlinedButton(onPressed: _busy ? null : () => _resolve(useRemote: true), child: const Text('Взять облачную версию')),
          OutlinedButton(onPressed: _busy ? null : () => _resolve(useRemote: false), child: const Text('Взять версию с телефона')),
        ],
      ],
    ),
  );
}
