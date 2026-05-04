import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/constants/app_constants.dart';

class CultureQuestApp extends ConsumerWidget {
  const CultureQuestApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: AppConstants.appName,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      // router: ref.watch(routerProvider),
      home: const Scaffold(
        body: Center(
          child: Text('CultureQuest', style: TextStyle(fontSize: 24)),
        ),
      ),
    );
  }
}
