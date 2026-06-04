import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../auth/providers/auth_provider.dart';
import '../../federated/providers/fl_provider.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/local_data_service.dart';
import '../../map/providers/map_provider.dart';
import '../../federated/providers/fl_provider.dart';

const _categories = [
  (id: 'art', label: 'Art', icon: Icons.palette_outlined),
  (id: 'architecture', label: 'Architecture', icon: Icons.account_balance_outlined),
  (id: 'history', label: 'History', icon: Icons.history_edu_outlined),
  (id: 'gastronomy', label: 'Gastronomy', icon: Icons.restaurant_outlined),
  (id: 'nature', label: 'Nature', icon: Icons.park_outlined),
  (id: 'music', label: 'Music', icon: Icons.music_note_outlined),
];

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.watch(authProvider).user;
    final flState = ref.watch(flProvider);

    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final initials = user.name.trim().split(' ').map((w) => w.isNotEmpty ? w[0].toUpperCase() : '').take(2).join();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        children: [
          // Avatar + name
          Center(
            child: Column(children: [
              CircleAvatar(
                radius: 44,
                backgroundColor: theme.colorScheme.primary,
                child: Text(
                  initials,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 32),
                ),
              ),
              const SizedBox(height: 14),
              Text(user.name, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(user.email, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ]),
          ),

          const SizedBox(height: 28),

          // Stats row
          Row(children: [
            Expanded(child: _StatCard(value: '${user.points}', label: 'Points', icon: Icons.star_rounded, color: Colors.amber)),
            const SizedBox(width: 12),
            Expanded(child: _StatCard(value: '${user.completedQuests}', label: 'Quests', icon: Icons.task_alt_rounded, color: theme.colorScheme.primary)),
          ]),

          const SizedBox(height: 12),

          // Reward hint
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.amber.withOpacity(0.25)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.local_activity_outlined, color: Colors.amber, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Earn more points and complete quests to unlock entry-fee discounts at museums, galleries and other paid attractions across the city!',
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
                ),
              ),
            ]),
          ),

          const SizedBox(height: 28),

          // Interests
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Interests', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              TextButton.icon(
                onPressed: () => context.push('/interests'),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Edit'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _categories.map((cat) {
              final active = user.interests.contains(cat.id);
              return FilterChip(
                avatar: Icon(cat.icon, size: 16),
                label: Text(cat.label),
                selected: active,
                onSelected: null,
                showCheckmark: false,
              );
            }).toList(),
          ),

          const SizedBox(height: 28),

          // Federated Learning status
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.2)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.hub_outlined, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Federated Learning', style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
                const Spacer(),
                if (flState.isTraining)
                  const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                _FLStat(label: 'Round', value: '${flState.round}'),
                const SizedBox(width: 20),
                _FLStat(label: 'Pending', value: '${flState.pendingInteractions}'),
              ]),
              if (flState.lastResult != null) ...[
                const SizedBox(height: 8),
                Text(flState.lastResult!, style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant)),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  onPressed: flState.isTraining || flState.pendingInteractions == 0
                      ? null
                      : () => ref.read(flProvider.notifier).runRound(),
                  child: Text(flState.pendingInteractions == 0
                      ? 'No pending interactions'
                      : 'Sync ${flState.pendingInteractions} interaction${flState.pendingInteractions == 1 ? '' : 's'}'),
                ),
              ),
            ]),
          ),

          const SizedBox(height: 36),

          // Clear local data
          OutlinedButton.icon(
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Clear local data?'),
                  content: const Text(
                    'This will erase your visited landmarks, personal ratings, completed quests, and saved routes stored on this device. Server data is not affected.',
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                    FilledButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        // 1. Clear all local storage only — server data is untouched
                        await ref.read(localDataProvider).clearAll();
                        // 2. Clear pending FL interactions
                        ref.read(flProvider.notifier).clearBuffer();
                        // 3. Refresh map landmark annotations
                        ref.read(mapProvider.notifier).fetchAllLandmarks();
                        ref.read(mapProvider.notifier).fetchMyRoutes();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Local data and progress cleared.')),
                          );
                        }
                      },
                      style: FilledButton.styleFrom(backgroundColor: Colors.orange),
                      child: const Text('Clear'),
                    ),
                  ],
                ),
              );
            },
            icon: const Icon(Icons.delete_sweep_outlined),
            label: const Text('Clear local data'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 12),

          // Logout
          OutlinedButton.icon(
            onPressed: () {
              ref.read(authProvider.notifier).logout();
            },
            icon: Icon(Icons.logout, color: theme.colorScheme.error),
            label: Text('Logout', style: TextStyle(color: theme.colorScheme.error)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: theme.colorScheme.error.withOpacity(0.5)),
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _FLStat extends StatelessWidget {
  final String label;
  final String value;
  const _FLStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(value, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
      Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    ]);
  }
}

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color color;

  const _StatCard({required this.value, required this.label, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 32),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: color)),
          Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ]),
      ]),
    );
  }
}
