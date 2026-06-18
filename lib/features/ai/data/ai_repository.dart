import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../domain/chat_message.dart';

/// The AI's reply plus how many questions the user has left today.
class AiReply {
  const AiReply(this.text, {this.remaining, this.limit});
  final String text;
  final int? remaining;
  final int? limit;
}

/// Thrown when the caller has hit their daily AI question limit.
class AiLimitException implements Exception {
  const AiLimitException(this.message, {this.limit});
  final String message;
  final int? limit;
  @override
  String toString() => message;
}

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
  ///
  /// Throws [AiLimitException] when the daily question limit is reached.
  Future<AiReply> chat(
    String tankId,
    List<ChatMessage> history, {
    bool includePhotos = false,
  }) async {
    try {
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
        return AiReply(
          data['recommendation'] as String,
          remaining: _asInt(data['usage']?['remaining']),
          limit: _asInt(data['usage']?['limit']),
        );
      }
      if (data is Map && data['error'] != null) {
        throw Exception(data['error'].toString());
      }
      throw Exception('Unexpected response from ai-recommend function.');
    } on FunctionException catch (e) {
      // Non-2xx responses (e.g. the 429 rate limit) arrive here.
      final details = e.details;
      if (details is Map) {
        if (details['code'] == 'rate_limited') {
          throw AiLimitException(
            details['error']?.toString() ??
                'Daily AI question limit reached.',
            limit: _asInt(details['usage']?['limit']),
          );
        }
        if (details['error'] != null) {
          throw Exception(details['error'].toString());
        }
      }
      throw Exception('AI request failed (${e.status}).');
    }
  }

  static int? _asInt(Object? v) =>
      v is int ? v : (v is num ? v.toInt() : null);
}

final aiRepositoryProvider = Provider<AiRepository>((ref) {
  return AiRepository(ref.watch(supabaseClientProvider));
});
