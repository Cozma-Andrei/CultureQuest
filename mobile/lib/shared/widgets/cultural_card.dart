import 'package:flutter/material.dart';
import '../models/landmark_model.dart';

class CulturalCard extends StatelessWidget {
  final LandmarkModel landmark;
  final VoidCallback? onTap;

  const CulturalCard({super.key, required this.landmark, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: onTap,
        title: Text(landmark.name),
        subtitle: Text(landmark.type),
        trailing: landmark.hasActiveQuest ? const Icon(Icons.star, color: Colors.amber) : null,
      ),
    );
  }
}
