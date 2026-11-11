import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite/sqflite.dart' as sqlite;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_client.dart';
import 'account_workspace.dart';
import 'guest_store.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key, required this.guest});
  final GuestStore guest;
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  late Future<SupabaseClient> _client;
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String _status = '';
  bool _deleted = false;

  @override
  void initState() {
    super.initState();
    _client = authClient();
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit(SupabaseClient client, {bool register = false}) async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      if (register) {
        final response = await client.auth.signUp(
          email: _email.text.trim(), password: _password.text,
        );
        if (mounted) setState(() {
          _deleted = false;
          _status = response.session == null
              ? 'Проверьте почту для подтверждения аккаунта. После подтверждения войдите.'
              : 'Аккаунт создан';
        });
      } else {
        await client.auth.signInWithPassword(
          email: _email.text.trim(), password: _password.text,
        );
        if (mounted) setState(() {
          _deleted = false;
          _status = 'Вход выполнен';
        });
      }
    } on AuthException {
      if (mounted) setState(() => _status =
          'Не удалось войти или зарегистрироваться. Проверьте данные, подтверждение почты и повторите позже.');
    } catch (_) {
      if (mounted) setState(() => _status = 'Ошибка подключения. Гостевой режим доступен без сети.');
    } finally {
      if (mounted) {
        _password.clear();
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _signOut(SupabaseClient client) async {
    setState(() => _busy = true);
    try {
      await client.auth.signOut(scope: SignOutScope.local);
      if (mounted) setState(() => _status = 'Вы вышли из аккаунта');
    } catch (_) {
      if (mounted) setState(() => _status = 'Не удалось завершить выход. Повторите попытку.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteAccount(SupabaseClient client, User user) async {
    final email = user.email;
    if (email == null || _busy) return;
    String password = '';
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить аккаунт и облачные копии?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Удаление необратимо. При необходимости сначала сохраните копию. Экспортированные файлы удаляются через «Мои файлы».'),
            TextField(
              obscureText: true,
              onChanged: (value) => password = value,
              decoration: const InputDecoration(labelText: 'Текущий пароль'),
            ),
          ],
        ),
        scrollable: true,
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить аккаунт')),
        ],
      ),
    );
    if (approved != true || !mounted || client.auth.currentUser?.id != user.id) return;
    if (password.isEmpty) {
      setState(() => _status = 'Для удаления нужен текущий пароль');
      return;
    }
    setState(() => _busy = true);
    try {
      final session = (await client.auth.signInWithPassword(email: email, password: password)).session;
      password = '';
      if (session == null || session.user.id != user.id) throw StateError('Account changed');
      final response = await client.functions.invoke('delete-account', headers: {
        'Authorization': 'Bearer ${session.accessToken}',
      });
      if (response.data is! Map || response.data['deleted'] != true) {
        throw StateError('Deletion not confirmed');
      }
      if (mounted) setState(() {
        _deleted = true;
        _status = 'Аккаунт и облачные копии удалены';
      });
      var localCleanup = true;
      try {
        await sqlite.deleteDatabase('account_${user.id}.db');
        await const FlutterSecureStorage().delete(key: 'assistant.memory.${user.id}');
      } catch (_) {
        localCleanup = false;
      }
      try {
        await client.auth.signOut(scope: SignOutScope.local);
      } catch (_) {
        await const SecureSessionStorage().removePersistedSession();
      }
      if (!localCleanup && mounted) {
        setState(() => _status = 'Аккаунт удалён. Локальную копию очистить не удалось.');
      }
    } catch (_) {
      if (mounted && !_deleted) {
        setState(() => _status = 'Сервер не подтвердил удаление. Проверьте пароль и подключение.');
      }
    } finally {
      password = '';
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Аккаунт')),
    body: FutureBuilder(
      future: _client,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: TextButton(
            onPressed: () => setState(() => _client = authClient()),
            child: const Text('Повторить подключение'),
          ));
        }
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final client = snapshot.data!;
        return StreamBuilder<AuthState>(
          stream: client.auth.onAuthStateChange,
          builder: (context, state) {
            final user = _deleted ? null : client.auth.currentUser;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('Данные аккаунта и гостевые записи хранятся отдельно.'),
                const SizedBox(height: 16),
                if (user != null) ...[
                  Text(user.email ?? 'Аккаунт'),
                  FilledButton(
                    onPressed: _busy ? null : () => Navigator.of(context).push<void>(
                      MaterialPageRoute(builder: (_) => AccountWorkspace(
                        client: client, accountId: user.id, guest: widget.guest,
                      )),
                    ),
                    child: const Text('Открыть данные аккаунта'),
                  ),
                  FilledButton(onPressed: _busy ? null : () => _signOut(client), child: const Text('Выйти')),
                  TextButton(onPressed: _busy ? null : () => _deleteAccount(client, user), child: const Text('Удалить аккаунт')),
                ] else
                  Form(
                    key: _form,
                    child: Column(children: [
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(labelText: 'Email'),
                        validator: (value) => value!.contains('@') ? null : 'Введите email',
                      ),
                      TextFormField(
                        controller: _password, obscureText: true,
                        decoration: const InputDecoration(labelText: 'Пароль'),
                        validator: (value) => value!.length >= 8 ? null : 'Не менее 8 символов',
                      ),
                      const SizedBox(height: 16),
                      FilledButton(onPressed: _busy ? null : () => _submit(client), child: const Text('Войти')),
                      TextButton(onPressed: _busy ? null : () => _submit(client, register: true), child: const Text('Создать аккаунт')),
                    ]),
                  ),
                if (_busy) const LinearProgressIndicator(),
                Text(_status),
              ],
            );
          },
        );
      },
    ),
  );
}
