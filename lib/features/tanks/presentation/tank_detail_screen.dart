import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/glass.dart';
import '../../health/data/health_repository.dart';
import '../../health/data/tank_photo_repository.dart';
import '../../health/domain/health_log.dart';
import '../../health/domain/tank_photo.dart';
import '../../parameters/data/parameter_repository.dart';
import '../../parameters/domain/parameter_reading.dart';
import '../../parameters/domain/parameter_type.dart';
import '../data/tank_repository.dart';
import '../domain/dosing.dart';
import '../domain/habitat.dart';
import '../domain/equipment.dart';
import '../domain/feeding.dart';
import '../domain/livestock.dart';
import '../domain/tank.dart';

class TankDetailScreen extends ConsumerWidget {
  const TankDetailScreen({super.key, required this.tankId});
  final String tankId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tankAsync = ref.watch(tankProvider(tankId));
    return Scaffold(
      appBar: AppBar(
        title: Text(tankAsync.maybeWhen(
            data: (t) => t.name, orElse: () => 'Tank')),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Edit tank',
            onPressed: () => context.push('/tanks/$tankId/edit'),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete tank',
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
      body: tankAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (tank) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(readingsProvider((tankId: tankId, parameterKey: null)));
            ref.invalidate(healthLogsProvider(tankId));
            ref.invalidate(tankPhotosProvider(tankId));
            ref.invalidate(equipmentProvider(tankId));
            ref.invalidate(livestockProvider(tankId));
            ref.invalidate(dosingProvider(tankId));
            ref.invalidate(feedingProvider(tankId));
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _Overview(tank: tank),
              const SizedBox(height: 16),
              _ActionsRow(tankId: tankId),
              const SizedBox(height: 16),
              _LatestReadings(tankId: tankId),
              const SizedBox(height: 16),
              _HealthSection(tankId: tankId),
              const SizedBox(height: 16),
              _EquipmentSection(tankId: tankId),
              const SizedBox(height: 16),
              _LivestockSection(tankId: tankId),
              const SizedBox(height: 16),
              _DosingSection(tankId: tankId),
              const SizedBox(height: 16),
              _FeedingSection(tankId: tankId),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete tank?'),
        content: const Text(
            'This permanently removes the tank and all its readings, equipment, livestock and dosing.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(tankRepositoryProvider).deleteTank(tankId);
    ref.invalidate(tanksProvider);
    if (context.mounted) context.go('/');
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.tank});
  final Tank tank;

  String? get _ageLabel {
    if (tank.startedOn == null) return null;
    final days = DateTime.now().difference(tank.startedOn!).inDays;
    if (days < 0) return null;
    if (days < 31) return '$days d';
    if (days < 365) return '${(days / 30).floor()} mo';
    final years = days / 365;
    return '${years.toStringAsFixed(years < 10 ? 1 : 0)} yr';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _StatChip(
                icon: switch (tank.habitat) {
                  Habitat.freshwater => Icons.water_drop_outlined,
                  Habitat.pond => Icons.forest_outlined,
                  _ => Icons.waves,
                },
                label: Habitat.label(tank.habitat),
              ),
              _StatChip(
                icon: Icons.straighten,
                label: '${tank.volumeLiters.toStringAsFixed(0)} L',
                sublabel: '${tank.volumeGallons.toStringAsFixed(0)} gal',
              ),
              if (tank.tankType != null)
                _StatChip(
                  icon: Icons.category_outlined,
                  label: tank.tankType!,
                ),
              if (_ageLabel != null)
                _StatChip(
                  icon: Icons.event_available_outlined,
                  label: _ageLabel!,
                  sublabel: 'running',
                ),
            ],
          ),
          if (tank.notes != null && tank.notes!.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(tank.notes!,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}

/// A compact icon + value pill used in the tank hero header.
class _StatChip extends StatelessWidget {
  const _StatChip({required this.icon, required this.label, this.sublabel});
  final IconData icon;
  final String label;
  final String? sublabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: scheme.primary.withValues(alpha: 0.10),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: scheme.primary),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              if (sublabel != null)
                Text(sublabel!,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionsRow extends StatelessWidget {
  const _ActionsRow({required this.tankId});
  final String tankId;
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => context.push('/tanks/$tankId/log'),
                icon: const Icon(Icons.add_chart),
                label: const Text('Log'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => context.push('/tanks/$tankId/chart'),
                icon: const Icon(Icons.show_chart),
                label: const Text('Graphs'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => context.push('/tanks/$tankId/recommend'),
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Analyze my tank & ask questions'),
          ),
        ),
      ],
    );
  }
}

class _LatestReadings extends ConsumerWidget {
  const _LatestReadings({required this.tankId});
  final String tankId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async =
        ref.watch(readingsProvider((tankId: tankId, parameterKey: null)));
    final types = ref.watch(tankParameterTypesProvider(tankId)).asData?.value ??
        const <ParameterType>[];

    return _Section(
      title: 'Latest readings',
      child: async.when(
        loading: () => const Center(child: Padding(
            padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
        error: (e, _) => Text('$e'),
        data: (readings) {
          if (readings.isEmpty) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No readings yet. Tap "Log" to record parameters.'),
            );
          }
          // latest reading per parameter
          final latest = <String, ParameterReading>{};
          for (final r in readings) {
            latest.putIfAbsent(r.parameterKey, () => r);
          }
          final tiles = latest.values.toList();
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final r in tiles)
                _ReadingChip(
                  reading: r,
                  type: types.cast<ParameterType?>().firstWhere(
                        (t) => t!.key == r.parameterKey,
                        orElse: () => null,
                      ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ReadingChip extends StatelessWidget {
  const _ReadingChip({required this.reading, required this.type});
  final ParameterReading reading;
  final ParameterType? type;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final inRange = type?.inRange(reading.value) ?? true;
    final label = type?.label ?? reading.parameterKey;
    final unit = type?.unit ?? '';
    final decimals = type?.decimals ?? 2;
    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: inRange ? scheme.outlineVariant : scheme.error,
          width: inRange ? 1 : 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(reading.value.toStringAsFixed(decimals),
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(
                          color: inRange ? null : scheme.error,
                          fontWeight: FontWeight.bold)),
              const SizedBox(width: 4),
              Text(unit, style: Theme.of(context).textTheme.bodySmall),
              if (!inRange) ...[
                const Spacer(),
                Icon(Icons.warning_amber, size: 16, color: scheme.error),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.action});
  final String title;
  final Widget child;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text(title,
                      style: Theme.of(context).textTheme.titleMedium)),
              if (action != null) action!,
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

// ---------- Health ----------
class _HealthSection extends ConsumerWidget {
  const _HealthSection({required this.tankId});
  final String tankId;

  Color _healthColor(int rating) {
    final hue = ((rating - 1) / 9) * 120;
    return HSLColor.fromAHSL(1, hue, 0.65, 0.45).toColor();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(healthLogsProvider(tankId));
    return _Section(
      title: 'Health',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          async.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('$e'),
            data: (logs) => _healthSummary(context, ref, logs),
          ),
          _HealthPhotosStrip(tankId: tankId),
        ],
      ),
    );
  }

  Widget _healthSummary(
      BuildContext context, WidgetRef ref, List<HealthLog> logs) {
          if (logs.isEmpty) {
            return const Text(
                'No health checks yet. Use "Log → Health" to rate the tank.');
          }
          final latest = logs.first;
          final color = _healthColor(latest.rating);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(color: color, width: 2),
                    ),
                    child: Text('${latest.rating}',
                        style: TextStyle(
                            color: color,
                            fontSize: 22,
                            fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${HealthLog.labelFor(latest.rating)} • '
                            '${latest.rating}/10',
                            style: Theme.of(context).textTheme.titleMedium),
                        Text(
                          latest.observedAt
                              .toLocal()
                              .toString()
                              .split('.')
                              .first,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (latest.notes != null && latest.notes!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(latest.notes!,
                    style: Theme.of(context).textTheme.bodyMedium),
              ],
              if (logs.length > 1) ...[
                const Divider(height: 24),
                Text('Recent checks',
                    style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 4),
                for (final log in logs.take(6).skip(1))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor:
                          _healthColor(log.rating).withValues(alpha: 0.18),
                      child: Text('${log.rating}',
                          style: TextStyle(
                              color: _healthColor(log.rating),
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                    ),
                    title: Text(
                      log.observedAt.toLocal().toString().split(' ').first,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    subtitle: log.notes == null || log.notes!.isEmpty
                        ? null
                        : Text(log.notes!,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () async {
                        await ref
                            .read(healthRepositoryProvider)
                            .deleteLog(log.id);
                        ref.invalidate(healthLogsProvider(tankId));
                      },
                    ),
                  ),
              ],
            ],
          );
  }
}

/// A horizontal strip of recent tank photos shown under the Health summary.
/// Tapping a photo opens it full-screen. Photos are added from Log → Health.
class _HealthPhotosStrip extends ConsumerWidget {
  const _HealthPhotosStrip({required this.tankId});
  final String tankId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(tankPhotosProvider(tankId));
    final photos = async.asData?.value ?? const <TankPhoto>[];
    if (photos.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 24),
        Text('Photos', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 8),
        SizedBox(
          height: 88,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: photos.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final p = photos[i];
              return GestureDetector(
                onTap: p.signedUrl == null
                    ? null
                    : () => _openViewer(context, p.signedUrl!),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: p.signedUrl == null
                      ? Container(
                          width: 88,
                          height: 88,
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          child: const Icon(Icons.image_outlined),
                        )
                      : Image.network(
                          p.signedUrl!,
                          width: 88,
                          height: 88,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 88,
                            height: 88,
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            child: const Icon(Icons.broken_image_outlined),
                          ),
                        ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _openViewer(BuildContext context, String url) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
          ),
          body: Center(
            child: InteractiveViewer(
              child: Image.network(url, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------- Equipment ----------
class _EquipmentSection extends ConsumerWidget {
  const _EquipmentSection({required this.tankId});
  final String tankId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(equipmentProvider(tankId));
    return _Section(
      title: 'Equipment',
      action: IconButton(
        icon: const Icon(Icons.add),
        onPressed: () => _addEquipmentDialog(context, ref, tankId),
      ),
      child: async.when(
        loading: () => const LinearProgressIndicator(),
        error: (e, _) => Text('$e'),
        data: (items) => items.isEmpty
            ? const Text('No equipment added.')
            : Column(
                children: [
                  for (final e in items)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(_equipIcon(e.category)),
                      title: Text(e.name),
                      subtitle: Text([
                        e.category,
                        if (e.brand != null) e.brand,
                        if (e.model != null) e.model,
                      ].whereType<String>().join(' • ')),
                      trailing: IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () async {
                          await ref
                              .read(tankRepositoryProvider)
                              .deleteEquipment(e.id);
                          ref.invalidate(equipmentProvider(tankId));
                        },
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  IconData _equipIcon(String category) => switch (category) {
        EquipmentCategory.light => Icons.light_mode,
        EquipmentCategory.filter => Icons.filter_alt,
        EquipmentCategory.skimmer => Icons.bubble_chart,
        EquipmentCategory.pump || EquipmentCategory.powerhead => Icons.air,
        EquipmentCategory.heater => Icons.thermostat,
        EquipmentCategory.chiller => Icons.ac_unit,
        EquipmentCategory.refugium => Icons.grass,
        EquipmentCategory.reactor => Icons.science,
        EquipmentCategory.ato => Icons.water_drop,
        EquipmentCategory.doser => Icons.medication_liquid,
        EquipmentCategory.controller => Icons.dashboard,
        _ => Icons.settings,
      };
}

Future<void> _addEquipmentDialog(
    BuildContext context, WidgetRef ref, String tankId) async {
  final name = TextEditingController();
  final brand = TextEditingController();
  final model = TextEditingController();
  String category = EquipmentCategory.light;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: const Text('Add equipment'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: EquipmentCategory.all
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setLocal(() => category = v!),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: brand,
                decoration:
                    const InputDecoration(labelText: 'Brand (optional)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: model,
                decoration:
                    const InputDecoration(labelText: 'Model (optional)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (name.text.trim().isEmpty) return;
              await ref.read(tankRepositoryProvider).addEquipment(Equipment(
                    id: '',
                    tankId: tankId,
                    name: name.text.trim(),
                    category: category,
                    brand: brand.text.trim().isEmpty ? null : brand.text.trim(),
                    model: model.text.trim().isEmpty ? null : model.text.trim(),
                  ));
              ref.invalidate(equipmentProvider(tankId));
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    ),
  );
}

// ---------- Livestock ----------
class _LivestockSection extends ConsumerWidget {
  const _LivestockSection({required this.tankId});
  final String tankId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(livestockProvider(tankId));
    return _Section(
      title: 'Livestock',
      action: IconButton(
        icon: const Icon(Icons.add),
        onPressed: () => _addLivestockDialog(context, ref, tankId),
      ),
      child: async.when(
        loading: () => const LinearProgressIndicator(),
        error: (e, _) => Text('$e'),
        data: (items) => items.isEmpty
            ? const Text('No livestock added.')
            : Column(
                children: [
                  for (final l in items)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                          '${l.name}${l.quantity > 1 ? ' ×${l.quantity}' : ''}'),
                      subtitle: Text([
                        l.kind.replaceAll('_', ' '),
                        if (l.species != null) l.species,
                      ].whereType<String>().join(' • ')),
                      trailing: IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () async {
                          await ref
                              .read(tankRepositoryProvider)
                              .deleteLivestock(l.id);
                          ref.invalidate(livestockProvider(tankId));
                        },
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

Future<void> _addLivestockDialog(
    BuildContext context, WidgetRef ref, String tankId) async {
  final name = TextEditingController();
  final species = TextEditingController();
  final qty = TextEditingController(text: '1');
  // Offer the kinds that suit this tank's habitat.
  final habitat =
      ref.read(tankProvider(tankId)).asData?.value.habitat ?? Habitat.saltwater;
  final kinds = LivestockKind.forHabitat(habitat);
  String kind = kinds.first;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: const Text('Add livestock'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration:
                    const InputDecoration(labelText: 'Common name'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: kind,
                decoration: const InputDecoration(labelText: 'Kind'),
                items: kinds
                    .map((k) => DropdownMenuItem(
                        value: k, child: Text(k.replaceAll('_', ' '))))
                    .toList(),
                onChanged: (v) => setLocal(() => kind = v!),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: species,
                decoration:
                    const InputDecoration(labelText: 'Species (optional)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: qty,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Quantity'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (name.text.trim().isEmpty) return;
              await ref.read(tankRepositoryProvider).addLivestock(Livestock(
                    id: '',
                    tankId: tankId,
                    name: name.text.trim(),
                    kind: kind,
                    species:
                        species.text.trim().isEmpty ? null : species.text.trim(),
                    quantity: int.tryParse(qty.text.trim()) ?? 1,
                  ));
              ref.invalidate(livestockProvider(tankId));
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    ),
  );
}

// ---------- Dosing ----------
class _DosingSection extends ConsumerWidget {
  const _DosingSection({required this.tankId});
  final String tankId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dosingProvider(tankId));
    return _Section(
      title: 'Dosing',
      action: IconButton(
        icon: const Icon(Icons.add),
        onPressed: () => _addDosingDialog(context, ref, tankId),
      ),
      child: async.when(
        loading: () => const LinearProgressIndicator(),
        error: (e, _) => Text('$e'),
        data: (items) => items.isEmpty
            ? const Text('No dosing schedule added.')
            : Column(
                children: [
                  for (final d in items)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(d.product),
                      subtitle: Text(
                          '${d.amount} ${d.unit} • ${d.frequency.replaceAll('_', ' ')}'
                          '${d.targetParameter != null ? ' → ${d.targetParameter}' : ''}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () async {
                          await ref
                              .read(tankRepositoryProvider)
                              .deleteDosing(d.id);
                          ref.invalidate(dosingProvider(tankId));
                        },
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

Future<void> _addDosingDialog(
    BuildContext context, WidgetRef ref, String tankId) async {
  final product = TextEditingController();
  final amount = TextEditingController();
  final unit = TextEditingController(text: 'mL');
  String frequency = DosingFrequency.daily;
  String? target;
  // The parameters this tank actually tracks (per its habitat).
  final params = ref.read(tankParameterTypesProvider(tankId)).asData?.value ??
      ParameterCatalog.builtIns;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: const Text('Add dosing'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: product,
                decoration: const InputDecoration(labelText: 'Product'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: amount,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: const InputDecoration(labelText: 'Amount'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 80,
                    child: TextField(
                      controller: unit,
                      decoration: const InputDecoration(labelText: 'Unit'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: frequency,
                decoration: const InputDecoration(labelText: 'Frequency'),
                items: DosingFrequency.all
                    .map((f) => DropdownMenuItem(
                        value: f, child: Text(f.replaceAll('_', ' '))))
                    .toList(),
                onChanged: (v) => setLocal(() => frequency = v!),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: target,
                decoration: const InputDecoration(
                    labelText: 'Targets parameter (optional)'),
                items: params
                    .map((p) =>
                        DropdownMenuItem(value: p.key, child: Text(p.label)))
                    .toList(),
                onChanged: (v) => setLocal(() => target = v),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final amt = double.tryParse(amount.text.trim());
              if (product.text.trim().isEmpty || amt == null) return;
              await ref.read(tankRepositoryProvider).addDosing(Dosing(
                    id: '',
                    tankId: tankId,
                    product: product.text.trim(),
                    amount: amt,
                    unit: unit.text.trim().isEmpty ? 'mL' : unit.text.trim(),
                    frequency: frequency,
                    targetParameter: target,
                  ));
              ref.invalidate(dosingProvider(tankId));
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    ),
  );
}

// ---------- Feeding ----------
class _FeedingSection extends ConsumerWidget {
  const _FeedingSection({required this.tankId});
  final String tankId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(feedingProvider(tankId));
    return _Section(
      title: 'Feeding schedule',
      action: IconButton(
        icon: const Icon(Icons.add),
        onPressed: () => _addFeedingDialog(context, ref, tankId),
      ),
      child: async.when(
        loading: () => const LinearProgressIndicator(),
        error: (e, _) => Text('$e'),
        data: (items) => items.isEmpty
            ? const Text('No feeding schedule added.')
            : Column(
                children: [
                  for (final f in items)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(f.food),
                      subtitle: Text([
                        if (f.amount != null && f.amount!.isNotEmpty) f.amount,
                        FeedingFrequency.label(f.frequency),
                        if (f.notes != null && f.notes!.isNotEmpty) f.notes,
                      ].whereType<String>().join(' • ')),
                      trailing: IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () async {
                          await ref
                              .read(tankRepositoryProvider)
                              .deleteFeeding(f.id);
                          ref.invalidate(feedingProvider(tankId));
                        },
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

Future<void> _addFeedingDialog(
    BuildContext context, WidgetRef ref, String tankId) async {
  final food = TextEditingController();
  final amount = TextEditingController();
  final notes = TextEditingController();
  String frequency = FeedingFrequency.onceDaily;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: const Text('Add feeding'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: food,
                decoration: const InputDecoration(
                    labelText: 'Food (e.g. Frozen mysis, Pellets, Nori)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: amount,
                decoration: const InputDecoration(
                    labelText: 'Amount (e.g. 1 cube, pinch) — optional'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: frequency,
                decoration: const InputDecoration(labelText: 'Frequency'),
                items: FeedingFrequency.all
                    .map((f) => DropdownMenuItem(
                        value: f, child: Text(FeedingFrequency.label(f))))
                    .toList(),
                onChanged: (v) => setLocal(() => frequency = v!),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: notes,
                decoration:
                    const InputDecoration(labelText: 'Notes (optional)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (food.text.trim().isEmpty) return;
              await ref.read(tankRepositoryProvider).addFeeding(Feeding(
                    id: '',
                    tankId: tankId,
                    food: food.text.trim(),
                    amount:
                        amount.text.trim().isEmpty ? null : amount.text.trim(),
                    frequency: frequency,
                    notes:
                        notes.text.trim().isEmpty ? null : notes.text.trim(),
                  ));
              ref.invalidate(feedingProvider(tankId));
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    ),
  );
}
