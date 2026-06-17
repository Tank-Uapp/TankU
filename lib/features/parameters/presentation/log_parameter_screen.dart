import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../health/data/health_repository.dart';
import '../../health/domain/health_log.dart';
import '../../health/presentation/daily_tank_photos.dart';
import '../data/parameter_repository.dart';
import '../domain/parameter_reading.dart';
import '../domain/parameter_type.dart';

enum _LogMode { reading, health }

class LogParameterScreen extends ConsumerStatefulWidget {
  const LogParameterScreen({super.key, required this.tankId});
  final String tankId;

  @override
  ConsumerState<LogParameterScreen> createState() => _LogParameterScreenState();
}

class _LogParameterScreenState extends ConsumerState<LogParameterScreen> {
  _LogMode _mode = _LogMode.reading;

  // Shared timestamp for whichever entry is being logged.
  DateTime _measuredAt = DateTime.now();
  bool _saving = false;
  String? _error;

  // Parameter reading state.
  ParameterType? _selected;
  final _value = TextEditingController();
  final _notes = TextEditingController();

  // Health check state.
  double _rating = 7;
  final _healthNotes = TextEditingController();

  @override
  void dispose() {
    _value.dispose();
    _notes.dispose();
    _healthNotes.dispose();
    super.dispose();
  }

  Future<void> _saveReading() async {
    final type = _selected;
    final value = double.tryParse(_value.text.trim());
    if (type == null || value == null) {
      setState(() => _error = 'Pick a parameter and enter a numeric value.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(parameterRepositoryProvider).addReading(ParameterReading(
            id: '',
            tankId: widget.tankId,
            parameterKey: type.key,
            value: value,
            measuredAt: _measuredAt,
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          ));
      ref.invalidate(readingsProvider((tankId: widget.tankId, parameterKey: null)));
      ref.invalidate(
          readingsProvider((tankId: widget.tankId, parameterKey: type.key)));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Logged ${type.label}')),
        );
        _value.clear();
        _notes.clear();
        setState(() => _measuredAt = DateTime.now());
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveHealth() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(healthRepositoryProvider).addLog(HealthLog(
            id: '',
            tankId: widget.tankId,
            rating: _rating.round(),
            observedAt: _measuredAt,
            notes: _healthNotes.text.trim().isEmpty
                ? null
                : _healthNotes.text.trim(),
          ));
      ref.invalidate(healthLogsProvider(widget.tankId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Logged health: ${_rating.round()}/10')),
        );
        _healthNotes.clear();
        setState(() => _measuredAt = DateTime.now());
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Log'),
        actions: [
          TextButton.icon(
            onPressed: () => context.pop(),
            icon: const Icon(Icons.check),
            label: const Text('Done'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<_LogMode>(
              segments: const [
                ButtonSegment(
                  value: _LogMode.reading,
                  icon: Icon(Icons.science_outlined),
                  label: Text('Reading'),
                ),
                ButtonSegment(
                  value: _LogMode.health,
                  icon: Icon(Icons.favorite_outline),
                  label: Text('Health'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() {
                _mode = s.first;
                _error = null;
              }),
            ),
            const SizedBox(height: 20),
            if (_mode == _LogMode.reading)
              _ReadingForm(
                tankId: widget.tankId,
                selected: _selected,
                onSelect: (t) => setState(() => _selected = t),
                valueController: _value,
                notesController: _notes,
                onSubmit: _saveReading,
              )
            else
              _healthForm(context),
            const SizedBox(height: 12),
            _MeasuredAtTile(
              label: _mode == _LogMode.health ? 'Observed at' : 'Measured at',
              value: _measuredAt,
              onTap: _pickDateTime,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _saving
                  ? null
                  : (_mode == _LogMode.reading ? _saveReading : _saveHealth),
              icon: const Icon(Icons.save),
              label: Text(_saving
                  ? 'Saving…'
                  : (_mode == _LogMode.reading
                      ? 'Save reading'
                      : 'Save health check')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _healthForm(BuildContext context) {
    final rating = _rating.round();
    final color = _healthColor(context, rating);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('How healthy is the tank looking?',
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 12),
        Center(
          child: Column(
            children: [
              Text('$rating',
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(
                        color: color,
                        fontWeight: FontWeight.bold,
                      )),
              Text('${HealthLog.labelFor(rating)}  •  out of 10',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(color: color)),
            ],
          ),
        ),
        Slider(
          value: _rating,
          min: 1,
          max: 10,
          divisions: 9,
          label: '$rating',
          activeColor: color,
          onChanged: (v) => setState(() => _rating = v),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('1 · Struggling', style: TextStyle(fontSize: 12)),
              Text('10 · Thriving', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _healthNotes,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Observations',
            alignLabelWithHint: true,
            hintText:
                'Describe how the reef looks — coral color & extension, fish '
                'behavior, algae, anything that needs improvement…',
          ),
        ),
        const SizedBox(height: 24),
        DailyTankPhotos(tankId: widget.tankId),
      ],
    );
  }

  Color _healthColor(BuildContext context, int rating) {
    // Red (1) → amber → green (10).
    final hue = ((rating - 1) / 9) * 120; // 0=red, 120=green
    return HSLColor.fromAHSL(1, hue, 0.65, 0.45).toColor();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _measuredAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_measuredAt),
    );
    setState(() {
      _measuredAt = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? _measuredAt.hour,
        time?.minute ?? _measuredAt.minute,
      );
    });
  }
}

/// The parameter-reading portion of the Log screen.
class _ReadingForm extends ConsumerWidget {
  const _ReadingForm({
    required this.tankId,
    required this.selected,
    required this.onSelect,
    required this.valueController,
    required this.notesController,
    required this.onSubmit,
  });

  final String tankId;
  final ParameterType? selected;
  final ValueChanged<ParameterType> onSelect;
  final TextEditingController valueController;
  final TextEditingController notesController;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final typesAsync = ref.watch(tankParameterTypesProvider(tankId));
    return typesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Text('$e'),
      data: (types) {
        final current = selected ?? types.first;
        if (selected == null) {
          WidgetsBinding.instance
              .addPostFrameCallback((_) => onSelect(types.first));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Parameter', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in types)
                  ChoiceChip(
                    label: Text(t.label),
                    selected: current.key == t.key,
                    onSelected: (_) => onSelect(t),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add, size: 18),
                  label: const Text('Custom'),
                  onPressed: () => _addCustomType(context, ref, onSelect),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: valueController,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Value',
                suffixText: current.unit,
                helperText: _rangeHint(current),
              ),
              onSubmitted: (_) => onSubmit(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notesController,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
              maxLines: 2,
            ),
          ],
        );
      },
    );
  }

  String? _rangeHint(ParameterType t) {
    if (t.idealMin == null && t.idealMax == null) return null;
    final lo = t.idealMin?.toStringAsFixed(t.decimals) ?? '—';
    final hi = t.idealMax?.toStringAsFixed(t.decimals) ?? '—';
    return 'Target reef range: $lo – $hi ${t.unit}';
  }
}

Future<void> _addCustomType(
  BuildContext context,
  WidgetRef ref,
  ValueChanged<ParameterType> onSelect,
) async {
  final key = TextEditingController();
  final label = TextEditingController();
  final unit = TextEditingController();
  final min = TextEditingController();
  final max = TextEditingController();
  final created = await showDialog<ParameterType>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Custom parameter'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: label,
              decoration:
                  const InputDecoration(labelText: 'Name (e.g. Potassium)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: unit,
              decoration: const InputDecoration(labelText: 'Unit (e.g. ppm)'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: min,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Ideal min'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: max,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Ideal max'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final name = label.text.trim();
            if (name.isEmpty) return;
            key.text = name
                .toLowerCase()
                .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
                .replaceAll(RegExp(r'^_|_$'), '');
            Navigator.pop(
              ctx,
              ParameterType(
                key: key.text,
                label: name,
                unit: unit.text.trim(),
                idealMin: double.tryParse(min.text.trim()),
                idealMax: double.tryParse(max.text.trim()),
                isCustom: true,
              ),
            );
          },
          child: const Text('Add'),
        ),
      ],
    ),
  );
  if (created == null) return;
  try {
    final saved =
        await ref.read(parameterRepositoryProvider).addCustomType(created);
    ref.invalidate(customParameterTypesProvider);
    onSelect(saved);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}

class _MeasuredAtTile extends StatelessWidget {
  const _MeasuredAtTile({
    required this.label,
    required this.value,
    required this.onTap,
  });
  final String label;
  final DateTime value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(value.toString().split('.').first),
      trailing: const Icon(Icons.edit_calendar),
      onTap: onTap,
    );
  }
}
