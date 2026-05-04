import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LandmarkDetailScreen extends ConsumerWidget {
  final String landmarkId;
  const LandmarkDetailScreen({super.key, required this.landmarkId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Scaffold(
      body: Placeholder(),
    );
  }
}
