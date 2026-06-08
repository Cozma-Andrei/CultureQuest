import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/local_data_service.dart';
import '../../auth/providers/auth_provider.dart';

class PrivacyScreen extends ConsumerWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.watch(authProvider).user;
    final local = ref.read(localDataProvider);

    final visitedCount    = local.getVisitedIds().length;
    final ratingsCount    = local.getAllRatings().length;
    final questsCount     = local.getCompletedQuestIds().length;
    final routesCount     = local.getRoutes().length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Privacy'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        children: [
          // Intro
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withOpacity(0.35),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.colorScheme.primary.withOpacity(0.2)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.shield_outlined, color: theme.colorScheme.primary, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'CultureQuest is built around local-first privacy. '
                  'Your personal behaviour stays on this device. '
                  'The server only holds the minimum it needs to run the app.',
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
                ),
              ),
            ]),
          ),

          const SizedBox(height: 28),

          // On this device
          _SectionHeader(
            icon: Icons.phone_android_outlined,
            label: 'Stored only on this device',
            color: Colors.green.shade700,
          ),
          const SizedBox(height: 12),
          _DataCard(children: [
            _DataRow(
              icon: Icons.place_outlined,
              label: 'Landmarks you visited',
              value: '$visitedCount',
              detail: 'The server only receives an anonymous +1 counter per visit.',
            ),
            _DataRow(
              icon: Icons.star_outline_rounded,
              label: 'Your personal ratings',
              value: '$ratingsCount',
              detail: 'Ratings are stored as a sum + count on the server - your individual choice is never recorded.',
            ),
            _DataRow(
              icon: Icons.task_alt_outlined,
              label: 'Completed quests',
              value: '$questsCount',
              detail: 'Which specific quests you answered, and how, is kept here.',
            ),
            _DataRow(
              icon: Icons.route_outlined,
              label: 'Saved routes',
              value: '$routesCount',
              detail: 'Your personal routes never leave this device.',
            ),
            _DataRow(
              icon: Icons.rate_review_outlined,
              label: 'Your review ID',
              value: 'local',
              detail: 'Your comment is stored anonymously on the server - only this device knows it belongs to you.',
            ),
          ]),

          const SizedBox(height: 24),

          // On the server
          _SectionHeader(
            icon: Icons.cloud_outlined,
            label: 'Stored on the server',
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 12),
          _DataCard(children: [
            _DataRow(
              icon: Icons.person_outline,
              label: 'Display name',
              value: user?.name ?? '-',
              detail: 'Used to show your name in the profile.',
            ),
            _DataRow(
              icon: Icons.star_rounded,
              label: 'Total points',
              value: '${user?.points ?? 0}',
              detail: 'Earned from completing quests and contributing content.',
            ),
            _DataRow(
              icon: Icons.checklist_outlined,
              label: 'Total quests completed',
              value: '${user?.completedQuests ?? 0}',
              detail: 'A count only - not which quests or when.',
            ),
            _DataRow(
              icon: Icons.interests_outlined,
              label: 'Interests',
              value: user?.interests.isEmpty == true ? 'none set' : user!.interests.join(', '),
              detail: 'Used to personalise landmark recommendations.',
            ),
          ]),

          const SizedBox(height: 24),

          // Never stored
          _SectionHeader(
            icon: Icons.visibility_off_outlined,
            label: 'What the server never sees',
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          _DataCard(children: [
            _NeverRow('Which landmarks you visited or when'),
            _NeverRow('Your individual star ratings per landmark'),
            _NeverRow('Your route history or saved routes'),
            _NeverRow('Which quests you completed'),
            _NeverRow('Your location history'),
            _NeverRow('Who wrote which review or story'),
          ]),

          const SizedBox(height: 24),

          // Federated Learning & model privacy
          _SectionHeader(
            icon: Icons.hub_outlined,
            label: 'AI model privacy',
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 12),
          _DataCard(children: [
            _DataRow(
              icon: Icons.model_training_outlined,
              label: 'Federated Learning',
              value: 'on-device',
              detail: 'Your interactions train the recommendation model locally. '
                  'Only weight updates are shared - never your raw visit data.',
            ),
            _DataRow(
              icon: Icons.noise_aware_outlined,
              label: 'Differential Privacy',
              value: 'enabled',
              detail: 'Gaussian noise is added to model updates before upload. '
                  'This prevents membership inference - even by querying the global '
                  'model, no one can determine whether you visited a specific landmark.',
            ),
            _DataRow(
              icon: Icons.content_cut_outlined,
              label: 'Update norm clipping',
              value: 'enabled',
              detail: 'Each update is clipped to a maximum size before aggregation, '
                  'limiting how much any single device (including a malicious one) '
                  'can shift the shared model.',
            ),
          ]),

          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceVariant.withOpacity(0.4),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.info_outline, size: 18, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Research (Shokri et al., 2017) shows that model weights alone can '
                  'reveal whether a specific data point was used in training - known as '
                  'a membership inference attack. The Differential Privacy noise above '
                  'provides a mathematical bound on this leakage.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    height: 1.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ]),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _SectionHeader({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 18, color: color),
      const SizedBox(width: 8),
      Text(label, style: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.bold, color: color)),
    ]);
  }
}

class _DataCard extends StatelessWidget {
  final List<Widget> children;
  const _DataCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Column(
        children: children.map((c) => c).toList(),
      ),
    );
  }
}

class _DataRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String detail;
  const _DataRow({required this.icon, required this.label, required this.value, required this.detail});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(label, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600))),
              Text(value, style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 3),
            Text(detail, style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant, height: 1.4)),
          ]),
        ),
      ]),
    );
  }
}

class _NeverRow extends StatelessWidget {
  final String text;
  const _NeverRow(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        Container(
          width: 3, height: 3,
          decoration: BoxDecoration(
            color: theme.colorScheme.onSurfaceVariant,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(text,
            style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant))),
      ]),
    );
  }
}
