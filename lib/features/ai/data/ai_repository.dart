import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../domain/chat_message.dart';

/// Talks to the `ai-recommend` Supabase Edge Function, which holds the
/// Venice AI key server-side. The app never sees the secret key.
class AiRepository {
  AiRepository(this._client);
  final SupabaseClient _client;

  /// Sends the conversation [history] for [tankId] and returns the AI's reply.
  /// Pass an empty [history] to get the initial analysis. The function always
  /// re-injects the tank's current data, so the AI stays grounded each turn.
  ///
  /// Set [includePhotos] to attach the tank's recent photos to the initial
  /// analysis (uses a vision model — slower and more costly), off by default.
  Future<String> chat(
    String tankId,
    List<ChatMessage> history, {
    bool includePhotos = false,
  }) async {
    final res = await _client.functions.invoke(
      'ai-recommend',
      body: {
        'tank_id': tankId,
        'messages': history.map((m) => m.toJson()).toList(),
        'include_photos': includePhotos,
      },
    );
    final data = res.data;
    if (data is Map && data['recommendation'] is String) {
      return data['recommendation'] as String;
    }
    if (data is Map && data['error'] != null) {
      throw Exception(data['error'].toString());
    }
    throw Exception('Unexpected response from ai-recommend function.');
  }
}

final aiRepositoryProvider = Provider<AiRepository>((ref) {
  return AiRepository(ref.watch(supabaseClientProvider));
});
