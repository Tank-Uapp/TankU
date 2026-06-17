import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../data/tank_photo_repository.dart';
import '../domain/tank_photo.dart';

/// Lets the user add up to [TankPhoto.dailyLimit] photos of a tank per day and
/// shows today's photos as thumbnails. Used in the Log → Health form.
class DailyTankPhotos extends ConsumerStatefulWidget {
  const DailyTankPhotos({super.key, required this.tankId});
  final String tankId;

  @override
  ConsumerState<DailyTankPhotos> createState() => _DailyTankPhotosState();
}

class _DailyTankPhotosState extends ConsumerState<DailyTankPhotos> {
  bool _busy = false;

  Future<void> _add(int todayCount) async {
    if (todayCount >= TankPhoto.dailyLimit) {
      _snack('You can add up to ${TankPhoto.dailyLimit} photos per day.');
      return;
    }
    final source = await _pickSource();
    if (source == null) return;

    setState(() => _busy = true);
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 2048,
        imageQuality: 85,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      // imageQuality < 100 makes image_picker re-encode to JPEG, so the stored
      // file is always a jpg regardless of the original format.
      await ref.read(tankPhotoRepositoryProvider).addPhoto(
            tankId: widget.tankId,
            bytes: bytes,
            fileExtension: 'jpg',
          );
      ref.invalidate(tankPhotosProvider(widget.tankId));
    } catch (e) {
      _snack('Could not add photo: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<ImageSource?> _pickSource() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from library'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(TankPhoto photo) async {
    try {
      await ref.read(tankPhotoRepositoryProvider).deletePhoto(photo);
      ref.invalidate(tankPhotosProvider(widget.tankId));
    } catch (e) {
      _snack('Could not delete photo: $e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(tankPhotosProvider(widget.tankId));
    final today = DateTime.now();
    final todays = async.asData?.value.where((p) => p.isOn(today)).toList() ??
        const <TankPhoto>[];
    final atLimit = todays.length >= TankPhoto.dailyLimit;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text("Today's photos",
                  style: theme.textTheme.labelLarge),
            ),
            Text('${todays.length}/${TankPhoto.dailyLimit}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: atLimit
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurfaceVariant,
                )),
          ],
        ),
        const SizedBox(height: 8),
        async.when(
          loading: () => const SizedBox(
            height: 96,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Text('Could not load photos: $e',
              style: TextStyle(color: theme.colorScheme.error)),
          data: (_) => SizedBox(
            height: 96,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final p in todays)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _Thumb(photo: p, onDelete: () => _delete(p)),
                  ),
                _AddTile(
                  busy: _busy,
                  enabled: !atLimit && !_busy,
                  onTap: () => _add(todays.length),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.photo, required this.onDelete});
  final TankPhoto photo;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 96,
      height: 96,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: photo.signedUrl == null
                ? Container(
                    color: scheme.surfaceContainerHighest,
                    child: const Icon(Icons.image_outlined),
                  )
                : Image.network(
                    photo.signedUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: scheme.surfaceContainerHighest,
                      child: const Icon(Icons.broken_image_outlined),
                    ),
                  ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: InkWell(
              onTap: onDelete,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(2),
                child: const Icon(Icons.close, size: 16, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({
    required this.busy,
    required this.enabled,
    required this.onTap,
  });
  final bool busy;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: enabled ? scheme.primary : scheme.outlineVariant,
            width: 1.5,
          ),
          color: scheme.primary.withValues(alpha: enabled ? 0.06 : 0.0),
        ),
        alignment: Alignment.center,
        child: busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_a_photo_outlined,
                      color: enabled ? scheme.primary : scheme.outline),
                  const SizedBox(height: 4),
                  Text('Add',
                      style: TextStyle(
                        fontSize: 12,
                        color: enabled ? scheme.primary : scheme.outline,
                      )),
                ],
              ),
      ),
    );
  }
}
