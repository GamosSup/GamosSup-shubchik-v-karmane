import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SecureSessionStorage extends LocalStorage {
  const SecureSessionStorage();
  static const _storage = FlutterSecureStorage();
  static const _key = 'shubchik.auth.session';

  @override
  Future<void> initialize() async {}

  @override
  Future<String?> accessToken() => _storage.read(key: _key);

  @override
  Future<bool> hasAccessToken() async => await accessToken() != null;

  @override
  Future<void> persistSession(String persistSessionString) =>
      _storage.write(key: _key, value: persistSessionString);

  @override
  Future<void> removePersistedSession() => _storage.delete(key: _key);
}

Future<SupabaseClient>? _initializing;

Future<SupabaseClient> authClient() => _initializing ??= _initialize();

Future<SupabaseClient> _initialize() async {
  try {
    final supabase = await Supabase.initialize(
      url: 'https://miikjtgczofhyraplujz.supabase.co',
      anonKey: 'sb_publishable_uikO6HY2gz36vcXAa4qK7A_NmAlgL51',
      authOptions: const FlutterAuthClientOptions(
        localStorage: SecureSessionStorage(),
        pkceAsyncStorage: _PkceStorage(),
      ),
    );
    return supabase.client;
  } catch (_) {
    _initializing = null;
    rethrow;
  }
}

class _PkceStorage extends GotrueAsyncStorage {
  const _PkceStorage();
  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> getItem({required String key}) => _storage.read(key: key);

  @override
  Future<void> setItem({required String key, required String value}) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> removeItem({required String key}) => _storage.delete(key: key);
}
