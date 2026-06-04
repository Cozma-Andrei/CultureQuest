import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/models/quest_model.dart';
import '../providers/quest_provider.dart';
import '../../federated/providers/fl_provider.dart';

class QuestScreen extends ConsumerStatefulWidget {
  final String landmarkId;
  final String landmarkName;
  final String landmarkType;
  final bool isNearby;

  const QuestScreen({
    super.key,
    required this.landmarkId,
    required this.landmarkName,
    required this.landmarkType,
    required this.isNearby,
  });

  @override
  ConsumerState<QuestScreen> createState() => _QuestScreenState();
}

class _QuestScreenState extends ConsumerState<QuestScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(questProvider.notifier).loadQuests(
            widget.landmarkId,
            landmarkName: widget.landmarkName,
            isNearby: widget.isNearby,
          );
    });
  }

  Future<void> _submit(String questId, {int? answerIndex, String? noteText}) async {
    final result = await ref.read(questProvider.notifier).completeQuest(
          questId,
          landmarkId: widget.landmarkId,
          answerIndex: answerIndex,
          noteText: noteText,
        );

    if (!mounted) return;

    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Something went wrong. Try again.')),
      );
      return;
    }

    if (result['already_completed'] == true) return;

    final correct = result['correct'] as bool;
    final pointsEarned = result['points_earned'] as int;

    if (correct && widget.landmarkType.isNotEmpty) {
      ref.read(flProvider.notifier).recordInteractionForType(widget.landmarkType, 0.8);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(correct
            ? (pointsEarned > 0 ? '+$pointsEarned points earned!' : 'Quest completed!')
            : 'Wrong answer — try again!'),
        backgroundColor: correct ? Colors.green.shade700 : Colors.red.shade700,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(questProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.landmarkName, overflow: TextOverflow.ellipsis),
        centerTitle: true,
      ),
      body: Builder(builder: (_) {
        if (state.isLoading) return const Center(child: CircularProgressIndicator());

        if (state.error != null) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 12),
              Text(state.error!, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => ref.read(questProvider.notifier).loadQuests(
                      widget.landmarkId,
                      landmarkName: widget.landmarkName,
                      isNearby: widget.isNearby,
                    ),
                child: const Text('Retry'),
              ),
            ]),
          );
        }

        if (state.quests.isEmpty) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.task_alt_outlined, size: 48, color: theme.colorScheme.outline),
              const SizedBox(height: 12),
              Text('No quests here yet.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ]),
          );
        }

        final done = state.quests.where((q) => q.completed).length;
        final total = state.quests.length;
        final totalPts = state.quests.fold(0, (s, q) => s + q.points);

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            // Progress header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(children: [
                Icon(Icons.emoji_events_outlined,
                    color: theme.colorScheme.primary, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('$done / $total quests completed',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: total == 0 ? 0 : done / total,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ]),
                ),
                const SizedBox(width: 12),
                Column(children: [
                  Text('$totalPts',
                      style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.amber.shade700)),
                  Text('pts',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ]),
              ]),
            ),

            if (!widget.isNearby) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Row(children: [
                  Icon(Icons.place_outlined, color: Colors.orange.shade700, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'You\'re not at this landmark yet. '
                      'Get within 100 m to complete quests.',
                      style: TextStyle(
                          color: Colors.orange.shade800,
                          fontSize: 12,
                          height: 1.4),
                    ),
                  ),
                ]),
              ),
            ],

            const SizedBox(height: 16),
            ...state.quests.map(
              (q) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _QuestCard(
                  quest: q,
                  isNearby: widget.isNearby,
                  onSubmit: _submit,
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}

// ── Quest card ────────────────────────────────────────────────────────────────

class _QuestCard extends StatefulWidget {
  final QuestModel quest;
  final bool isNearby;
  final Future<void> Function(String questId, {int? answerIndex, String? noteText}) onSubmit;

  const _QuestCard({
    required this.quest,
    required this.isNearby,
    required this.onSubmit,
  });

  @override
  State<_QuestCard> createState() => _QuestCardState();
}

class _QuestCardState extends State<_QuestCard> {
  int? _selected;
  final _noteCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || widget.quest.completed || !widget.isNearby) return;

    if (widget.quest.type == 'educational' && _selected == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Select an answer first')));
      return;
    }
    if (widget.quest.type == 'virtual_note' && _noteCtrl.text.trim().length < 3) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Write at least a few words')));
      return;
    }

    setState(() => _submitting = true);
    await widget.onSubmit(
      widget.quest.id,
      answerIndex: widget.quest.type == 'educational' ? _selected : null,
      noteText: widget.quest.type == 'virtual_note' ? _noteCtrl.text.trim() : null,
    );
    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = widget.quest;

    final borderColor = q.completed
        ? Colors.green.shade300
        : !widget.isNearby
            ? theme.colorScheme.outlineVariant
            : theme.colorScheme.outlineVariant;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: borderColor,
          width: q.completed ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Header ─────────────────────────────────────────────────────
          Row(children: [
            _TypeBadge(type: q.type),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.star_rounded, size: 14, color: Colors.amber.shade700),
                const SizedBox(width: 3),
                Text('${q.points} pts',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.amber.shade800)),
              ]),
            ),
            if (q.completed) ...[
              const SizedBox(width: 8),
              Icon(Icons.check_circle_rounded, color: Colors.green.shade600, size: 22),
            ] else if (!widget.isNearby) ...[
              const SizedBox(width: 8),
              Icon(Icons.lock_outline, color: Colors.grey.shade400, size: 20),
            ],
          ]),

          const SizedBox(height: 10),
          Text(q.title,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(q.description,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.4)),

          // ── Body depends on state ───────────────────────────────────────
          if (q.completed) ...[
            const SizedBox(height: 14),
            if (q.type == 'educational' && q.options.isNotEmpty)
              _CompletedOptions(options: q.options, correctIndex: q.correctOptionIndex)
            else
              _CompletedBanner(type: q.type),
          ] else if (!widget.isNearby) ...[
            // Missions/challenges show their description fully but are locked.
            // Educational quests deliberately hide the options so you can't
            // memorise the answer without visiting the place.
            if (q.type == 'mission' || q.type == 'challenge')
              const SizedBox.shrink(),
            const SizedBox(height: 10),
            _ProximityLockBanner(),
          ] else ...[
            const SizedBox(height: 14),
            if (q.type == 'educational' && q.options.isNotEmpty)
              _MultipleChoice(
                options: q.options,
                selected: _selected,
                onSelect: (i) => setState(() => _selected = i),
              ),
            if (q.type == 'virtual_note')
              TextField(
                controller: _noteCtrl,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'Write your note here…',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(q.type == 'mission' || q.type == 'challenge'
                        ? 'Mark as Done'
                        : 'Submit'),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

// ── Completion displays ───────────────────────────────────────────────────────

class _CompletedOptions extends StatelessWidget {
  final List<String> options;
  final int? correctIndex;

  const _CompletedOptions({required this.options, required this.correctIndex});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Correct answer',
            style: theme.textTheme.labelMedium?.copyWith(
                color: Colors.green.shade700, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        ...options.asMap().entries.map((e) {
          final isCorrect = e.key == correctIndex;
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isCorrect ? Colors.green.shade50 : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isCorrect ? Colors.green.shade400 : Colors.grey.shade200,
                width: isCorrect ? 1.5 : 1,
              ),
            ),
            child: Row(children: [
              Icon(
                isCorrect ? Icons.check_circle : Icons.circle_outlined,
                size: 18,
                color: isCorrect ? Colors.green.shade600 : Colors.grey.shade400,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(e.value,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isCorrect ? Colors.green.shade800 : Colors.grey.shade500,
                      fontWeight:
                          isCorrect ? FontWeight.w600 : FontWeight.normal,
                    )),
              ),
            ]),
          );
        }),
      ],
    );
  }
}

class _CompletedBanner extends StatelessWidget {
  final String type;
  const _CompletedBanner({required this.type});

  @override
  Widget build(BuildContext context) {
    final label = switch (type) {
      'mission' => 'Mission accomplished',
      'challenge' => 'Challenge completed',
      'virtual_note' => 'Note submitted',
      _ => 'Quest completed',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.green.shade300),
      ),
      child: Row(children: [
        Icon(Icons.check_circle_rounded, color: Colors.green.shade600, size: 18),
        const SizedBox(width: 8),
        Text(label,
            style: TextStyle(
                color: Colors.green.shade700,
                fontWeight: FontWeight.w600,
                fontSize: 13)),
      ]),
    );
  }
}

class _ProximityLockBanner extends StatelessWidget {
  const _ProximityLockBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(children: [
        Icon(Icons.lock_outline, color: Colors.grey.shade500, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Visit this landmark (within 100 m) to unlock',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        ),
      ]),
    );
  }
}

// ── Shared input widgets ──────────────────────────────────────────────────────

class _MultipleChoice extends StatelessWidget {
  final List<String> options;
  final int? selected;
  final ValueChanged<int> onSelect;

  const _MultipleChoice(
      {required this.options, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: options.asMap().entries.map((e) {
        final isSelected = selected == e.key;
        return GestureDetector(
          onTap: () => onSelect(e.key),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(children: [
              Icon(
                isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 18,
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(e.value,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isSelected
                          ? theme.colorScheme.onPrimaryContainer
                          : theme.colorScheme.onSurface,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                    )),
              ),
            ]),
          ),
        );
      }).toList(),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  final String type;
  const _TypeBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (type) {
      'educational' => ('Educational', Colors.blue),
      'challenge' => ('Challenge', Colors.deepOrange),
      'mission' => ('Mission', Colors.teal),
      'virtual_note' => ('Note', Colors.purple),
      _ => ('Quest', Colors.blueGrey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color.shade700,
              letterSpacing: 0.3)),
    );
  }
}
