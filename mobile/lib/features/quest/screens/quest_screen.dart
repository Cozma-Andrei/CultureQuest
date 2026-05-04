import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class QuestScreen extends ConsumerWidget {
  final String landmarkId;
  const QuestScreen({super.key, required this.landmarkId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Scaffold(
      body: Placeholder(),
    );
  }
}
