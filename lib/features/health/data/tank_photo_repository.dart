import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../domain/tank_photo.dart';

class TankPhotoRepository {
  TankPhotoRepository(this._client);
  final SupabaseClient _client;

  static const _bucket = 'tank-photos';

  /// How long a generated display URL stays valid.
  static const _signedUrlTtl = 60 * 60; // 1 hour

  /// Recent photos for a tank, newest first, each with a fresh signed URL.
  Future<List<TankPhoto>> listPhotos(String tankId, {int limit = 60}) async {
    final rows = await _client
        .from('tank_photos')
        .select()
        .eq('tank_id', tankId)
        .order('taken_on', ascending: false)
        .order('created_at', ascending: false)
        .limit(limit);
    final photos = rows.map(TankPhoto.fromJson).toList();
    if (photos.isEmpty) return photos;

    // Resolve display URLs in one batch call.
    final signed = await _client.storage.from(_bucket).createSignedUrls(
          photos.map((p) => p.storagePath).toList(),
          _signedUrlTtl,
        );
    final urlByPath = {
      for (final s in signed) s.path: s.signedUrl,
    };
    return [
      for (final p in photos) p.copyWith(signedUrl: urlByPath[p.storagePath]),
    ];
  }

  /// Uploads [bytes] for [tankId] and records it. Caller must enforce the
  /// per-day limit before calling (see [TankPhoto.dailyLimit]).
  Future<TankPhoto> addPhoto({
    required String tankId,
    required Uint8List bytes,
    String fileExtension = 'jpg',
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Must be signed in to upload photos.');
    }
    final name = '${DateTime.now().microsecondsSinceEpoch}.$fileExtension';
    final path = '$userId/$tankId/$name';

    await _client.storage.from(_bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: _contentTypeFor(fileExtension),
            upsert: false,
          ),
        );

    try {
      final row = await _client
          .from('tank_photos')
          .insert({'tank_id': tankId, 'storage_path': path})
          .select()
          .single();
      return TankPhoto.fromJson(row);
    } catch (e) {
      // Don't leave an orphaned object if the row insert failed.
      try {
        await _client.storage.from(_bucket).remove([path]);
      } catch (_) {
        // Best-effort cleanup; surface the original error below.
      }
      rethrow;
    }
  }

  /// Removes both the storage object and its row.
  Future<void> deletePhoto(TankPhoto photo) async {
    await _client.storage.from(_bucket).remove([photo.storagePath]);
    await _client.from('tank_photos').delete().eq('id', photo.id);
  }

  String _contentTypeFor(String ext) => switch (ext.toLowerCase()) {
        'png' => 'image/png',
        'heic' => 'image/heic',
        'webp' => 'image/webp',
        _ => 'image/jpeg',
      };
}

final tankPhotoRepositoryProvider = Provider<TankPhotoRepository>((ref) {
  return TankPhotoRepository(ref.watch(supabaseClientProvider));
});

/// Recent photos for a tank, newest first (with signed display URLs).
final tankPhotosProvider =
    FutureProvider.family<List<TankPhoto>, String>((ref, tankId) async {
  return ref.watch(tankPhotoRepositoryProvider).listPhotos(tankId);
});
