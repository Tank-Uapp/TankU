import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';

class AuthRepository {
  AuthRepository(this._client);
  final SupabaseClient _client;

  Future<void> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async {
    await _client.auth.signUp(
      email: email,
      password: password,
      data: displayName == null ? null : {'display_name': displayName},
    );
  }

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signOut() => _client.auth.signOut();

  Future<void> sendPasswordReset(String email) =>
      _client.auth.resetPasswordForEmail(email);

  /// Permanently deletes the signed-in user's account and all their data, then
  /// signs out locally. Backed by the `delete-account` edge function, which
  /// holds the service-role key (account deletion can't be done client-side).
  Future<void> deleteAccount() async {
    try {
      final res = await _client.functions.invoke('delete-account');
      final data = res.data;
      if (data is Map && data['ok'] == true) {
        await _client.auth.signOut();
        return;
      }
      throw Exception((data is Map && data['error'] != null)
          ? data['error'].toString()
          : 'Account deletion failed.');
    } on FunctionException catch (e) {
      final details = e.details;
      throw Exception((details is Map && details['error'] != null)
          ? details['error'].toString()
          : 'Account deletion failed (${e.status}).');
    }
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(supabaseClientProvider));
});
