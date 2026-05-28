import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/register_screen.dart';
import '../../features/onboarding/screens/onboarding_screen.dart';
import '../../features/onboarding/screens/interests_screen.dart';
import '../../features/map/screens/map_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/quest/screens/quest_screen.dart';

class _AuthListenable extends ChangeNotifier {
  _AuthListenable(Ref ref) {
    ref.listen(authProvider, (_, __) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: _AuthListenable(ref),
    redirect: (context, state) {
      final auth = ref.read(authProvider);

      if (!auth.isInitialized) return '/splash';

      final path = state.matchedLocation;
      final unauthRoutes = {'/onboarding', '/login', '/register'};
      final setupRoutes = {'/onboarding', '/login', '/register'};

      if (path == '/splash') return auth.isLoggedIn ? '/' : '/onboarding';
      if (!auth.isLoggedIn && !unauthRoutes.contains(path)) return '/onboarding';
      if (auth.isLoggedIn && auth.needsInterests && path != '/interests') return '/interests';
      if (auth.isLoggedIn && !auth.needsInterests && setupRoutes.contains(path)) return '/';

      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (_, __) => const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
      GoRoute(path: '/interests', builder: (_, __) => const InterestsScreen()),
      GoRoute(path: '/', builder: (_, __) => const MapScreen()),
      GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
      GoRoute(
        path: '/quests/:landmarkId',
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return QuestScreen(
            landmarkId: state.pathParameters['landmarkId']!,
            landmarkName: extra['name'] as String? ?? '',
            landmarkType: extra['type'] as String? ?? '',
            isNearby: extra['isNearby'] as bool? ?? false,
          );
        },
      ),
    ],
  );
});
