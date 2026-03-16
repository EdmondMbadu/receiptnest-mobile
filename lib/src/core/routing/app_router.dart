import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/presentation/admin_screen.dart';
import '../../features/ai/presentation/ai_insights_screen.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/auth/presentation/verify_email_screen.dart';
import '../../features/folders/presentation/category_detail_screen.dart';
import '../../features/folders/presentation/folder_detail_screen.dart';
import '../../features/folders/presentation/folders_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/pricing/presentation/pricing_screen.dart';
import '../../features/receipts/presentation/receipt_detail_screen.dart';
import '../../features/share/presentation/share_view_screen.dart';
import '../../features/shell/presentation/app_shell_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/static/presentation/landing_screen.dart';
import '../../features/static/presentation/support_screen.dart';
import '../../features/static/presentation/terms_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authStream = ref.watch(authRepositoryProvider).authStateChanges;
  final authValue = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/',
    debugLogDiagnostics: kDebugMode,
    refreshListenable: GoRouterRefreshStream(authStream),
    redirect: (context, state) {
      if (authValue.isLoading) return null;

      final user = authValue.valueOrNull;
      final loggedIn = user != null;
      final verified = user?.emailVerified ?? false;

      final path = state.uri.path;
      final inApp = path.startsWith('/app');
      final isAuthRoute = path == '/login' || path == '/register';
      final isVerifyRoute = path == '/verify';
      final isPublicRoute =
          path == '/' ||
          path == '/support' ||
          path == '/terms' ||
          path.startsWith('/share/');

      if (!loggedIn && inApp) {
        return '/login';
      }

      if (!loggedIn && isVerifyRoute) {
        return '/login';
      }

      if (loggedIn && !verified && !isVerifyRoute) {
        return '/verify';
      }

      if (loggedIn &&
          verified &&
          (path == '/' || isAuthRoute || isVerifyRoute)) {
        return '/app/home';
      }

      if (!loggedIn && isPublicRoute) {
        return null;
      }

      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const LandingScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/verify',
        builder: (context, state) => const VerifyEmailScreen(),
      ),
      GoRoute(
        path: '/support',
        builder: (context, state) => const SupportScreen(),
      ),
      GoRoute(path: '/terms', builder: (context, state) => const TermsScreen()),
      GoRoute(
        path: '/share/:id',
        builder: (context, state) =>
            ShareViewScreen(shareId: state.pathParameters['id'] ?? ''),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            AppShellScreen(location: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: '/app/home',
            pageBuilder: (context, state) =>
                _noTransitionPage(state: state, child: const HomeScreen()),
          ),
          GoRoute(
            path: '/app/insights',
            pageBuilder: (context, state) => _noTransitionPage(
              state: state,
              child: const AiInsightsScreen(),
            ),
          ),
          GoRoute(
            path: '/app/folders',
            pageBuilder: (context, state) =>
                _noTransitionPage(state: state, child: const FoldersScreen()),
          ),
          GoRoute(
            path: '/app/settings',
            pageBuilder: (context, state) =>
                _noTransitionPage(state: state, child: const SettingsScreen()),
          ),
        ],
      ),
      GoRoute(
        path: '/app/receipt/:id',
        builder: (context, state) =>
            ReceiptDetailScreen(receiptId: state.pathParameters['id'] ?? ''),
      ),
      GoRoute(
        path: '/app/folders/:id',
        builder: (context, state) =>
            FolderDetailScreen(folderId: state.pathParameters['id'] ?? ''),
      ),
      GoRoute(
        path: '/app/categories/:id',
        builder: (context, state) =>
            CategoryDetailScreen(categoryId: state.pathParameters['id'] ?? ''),
      ),
      GoRoute(
        path: '/app/pricing',
        builder: (context, state) => const PricingScreen(),
      ),
      GoRoute(
        path: '/app/admin',
        builder: (context, state) => const AdminScreen(),
      ),
    ],
  );
});

NoTransitionPage<void> _noTransitionPage({
  required GoRouterState state,
  required Widget child,
}) {
  return NoTransitionPage<void>(key: state.pageKey, child: child);
}

class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<User?> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final StreamSubscription<User?> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
