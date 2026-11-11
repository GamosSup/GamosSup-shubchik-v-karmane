import 'package:flutter/material.dart';
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
        if (mounted) setState(() => _status = response.session == null
            ? 'Проверьте почту для подтверждения аккаунта. После подтверждения войдите.'
            : 'Аккаунт создан');
      } else {
        await client.auth.signInWithPassword(
          email: _email.text.trim(), password: _password.text,
        );
        if (mounted) setState(() => _status = 'Вход выполнен');
      }
    } on AuthException {
      if (mounted) setState(() => _status =
          'Не удалось войти или зарегистрироваться. Проверьте данные, подтверждение почты и повторите позже.');
    } catch (_) {
      if (mounted) setState(() => _status = 'Ошибка подключения. Гостевой режим доступен без сети.');
    } finally {
      _password.clear();
      if (mounted) setState(() => _busy = false);
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
            final user = client.auth.currentUser;
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
