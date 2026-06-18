import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase/supabase_providers.dart';
import '../features/auth/presentation/settings_screen.dart';
import '../features/auth/presentation/sign_in_screen.dart';
import '../features/auth/presentation/sign_up_screen.dart';
import '../features/parameters/presentation/chart_screen.dart';
import '../features/parameters/presentation/log_parameter_screen.dart';
import '../features/ai/presentation/recommendations_screen.dart';
import '../features/tanks/presentation/tank_detail_screen.dart';
import '../features/tanks/presentation/tank_form_screen.dart';
import '../features/tanks/presentation/tanks_list_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthRefresh(ref.watch(supabaseClientProvider));
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final loggedIn = ref.read(supabaseClientProvider).auth.currentUser != null;
      final loggingIn =
          state.matchedLocation == '/sign-in' || state.matchedLocation == '/sign-up';

      if (!loggedIn) return loggingIn ? null : '/sign-in';
      if (loggingIn) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/sign-in', builder: (_, __) => const SignInScreen()),
      GoRoute(path: '/sign-up', builder: (_, __) => const SignUpScreen()),
      GoRoute(path: '/', builder: (_, __) => const TanksListScreen()),
      GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
      GoRoute(
        path: '/tanks/new',
        builder: (_, __) => const TankFormScreen(),
      ),
      GoRoute(
        path: '/tanks/:id',
        builder: (_, s) => TankDetailScreen(tankId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/tanks/:id/edit',
        builder: (_, s) => TankFormScreen(tankId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/tanks/:id/log',
        builder: (_, s) =>
            LogParameterScreen(tankId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/tanks/:id/chart',
        builder: (_, s) => ChartScreen(tankId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/tanks/:id/recommend',
        builder: (_, s) =>
            RecommendationsScreen(tankId: s.pathParameters['id']!),
      ),
    ],
  );
});

/// Notifies go_router whenever Supabase auth state changes.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(SupabaseClient client) {
    _sub = client.auth.onAuthStateChange.listen((_) => notifyListeners());
  }
  late final StreamSubscription<AuthState> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
