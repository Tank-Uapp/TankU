import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../health/data/tank_photo_repository.dart';
import '../data/ai_repository.dart';
import '../domain/chat_message.dart';

class RecommendationsScreen extends ConsumerStatefulWidget {
  const RecommendationsScreen({super.key, required this.tankId});
  final String tankId;

  @override
  ConsumerState<RecommendationsScreen> createState() =>
      _RecommendationsScreenState();
}

class _RecommendationsScreenState
    extends ConsumerState<RecommendationsScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  final List<ChatMessage> _messages = [];
  bool _loading = false;
  String? _error;

  /// Whether to attach tank photos to the initial analysis (vision model —
  /// slower and more costly, so off by default).
  bool _usePhotos = false;

  @override
  void initState() {
    super.initState();
    // Generate the opening analysis once the first frame is up.
    WidgetsBinding.instance.addPostFrameCallback((_) => _startIfNeeded());
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _startIfNeeded() async {
    if (_messages.isNotEmpty || _loading) return;
    await _run(sendHistory: const []);
  }

  Future<void> _send() => _sendText(_input.text);

  Future<void> _sendText(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || _loading) return;
    _input.clear();
    setState(() {
      _messages.add(ChatMessage.user(text));
      _error = null;
    });
    _scrollToBottom();
    await _run(sendHistory: List.of(_messages));
  }

  Future<void> _reset() async {
    setState(() {
      _messages.clear();
      _error = null;
    });
    await _startIfNeeded();
  }

  /// Photos only affect the initial analysis, so changing the toggle restarts
  /// the conversation with the new setting.
  Future<void> _setUsePhotos(bool value) async {
    if (_loading || value == _usePhotos) return;
    setState(() => _usePhotos = value);
    await _reset();
  }

  Future<void> _retry() async {
    if (_loading) return;
    await _run(sendHistory: List.of(_messages));
  }

  Future<void> _run({required List<ChatMessage> sendHistory}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    _scrollToBottom();
    try {
      final reply = await ref.read(aiRepositoryProvider).chat(
            widget.tankId,
            sendHistory,
            includePhotos: _usePhotos,
          );
      if (!mounted) return;
      setState(() {
        _messages.add(ChatMessage.assistant(reply));
        _loading = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  /// A switch to include tank photos in the analysis. Only shown when the tank
  /// actually has photos, so it doesn't clutter the screen otherwise.
  Widget _buildPhotoToggle(BuildContext context) {
    final hasPhotos =
        ref.watch(tankPhotosProvider(widget.tankId)).asData?.value.isNotEmpty ??
            false;
    if (!hasPhotos) return const SizedBox.shrink();
    return SwitchListTile(
      value: _usePhotos,
      onChanged: _loading ? null : _setUsePhotos,
      dense: true,
      secondary: const Icon(Icons.photo_library_outlined),
      title: const Text('Analyze tank photos'),
      subtitle: const Text('Adds visual progress — slower, uses more credits'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final itemCount = _messages.length + (_loading ? 1 : 0);
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI advisor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Start over',
            onPressed: _loading ? null : _reset,
          ),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: const Padding(
              padding: EdgeInsets.all(10),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Ask about your tank, whether a fish is a good addition, '
                      'or for general recommendations. Grounded in your tank '
                      'data — verify before making changes.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          _buildPhotoToggle(context),
          Expanded(
            child: _messages.isEmpty && _loading
                ? const _ThinkingFull()
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: itemCount,
                    itemBuilder: (context, i) {
                      if (i >= _messages.length) return const _TypingBubble();
                      return _Bubble(message: _messages[i]);
                    },
                  ),
          ),
          if (_error != null)
            _ErrorBar(
              message: _error!,
              onRetry: _loading ? null : _retry,
            ),
          const _Examples(),
          _InputBar(
            controller: _input,
            enabled: !_loading,
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isUser = message.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser ? scheme.primary : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: SelectableText(
          message.content,
          style: TextStyle(
            color: isUser ? scheme.onPrimary : scheme.onSurface,
            height: 1.35,
          ),
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _ThinkingFull extends StatelessWidget {
  const _ThinkingFull();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Analyzing your reef…'),
        ],
      ),
    );
  }
}

class _ErrorBar extends StatelessWidget {
  const _ErrorBar({required this.message, required this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 18, color: scheme.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style:
                    TextStyle(color: scheme.onErrorContainer, fontSize: 12),
              ),
            ),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _Examples extends StatelessWidget {
  const _Examples();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Text(
        'Try asking: “Is this fish a good addition?” · '
        '“What should I add next?” · “How are my parameters?”',
        style: TextStyle(
          fontSize: 12,
          fontStyle: FontStyle.italic,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.enabled,
    required this.onSend,
  });
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: enabled,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) {
                  if (enabled) onSend();
                },
                decoration: const InputDecoration(
                  hintText: 'Ask a follow-up…',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: enabled ? onSend : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size(48, 48),
                padding: EdgeInsets.zero,
                shape: const CircleBorder(),
              ),
              child: const Icon(Icons.send, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}
