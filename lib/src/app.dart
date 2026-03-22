import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/models/user_profile.dart';
import 'features/notifications/data/push_notification_repository.dart';

class ReceiptNestApp extends ConsumerStatefulWidget {
  const ReceiptNestApp({super.key});

  @override
  ConsumerState<ReceiptNestApp> createState() => _ReceiptNestAppState();
}

class _ReceiptNestAppState extends ConsumerState<ReceiptNestApp> {
  ProviderSubscription<AsyncValue<UserProfile?>>? _profileSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;

  @override
  void initState() {
    super.initState();
    final pushRepository = ref.read(pushNotificationRepositoryProvider);

    _profileSubscription = ref.listenManual<AsyncValue<UserProfile?>>(
      currentUserProfileProvider,
      (previous, next) {
        final previousProfile = previous?.valueOrNull;
        final nextProfile = next.valueOrNull;

        if (previousProfile != null && nextProfile == null) {
          unawaited(pushRepository.unlinkCurrentDevice(previousProfile.id));
        }

        if (nextProfile != null) {
          unawaited(
            pushRepository.syncForUser(
              userId: nextProfile.id,
              settings: nextProfile.notificationSettings,
            ),
          );
        }
      },
      fireImmediately: true,
    );

    _tokenRefreshSubscription = pushRepository.tokenRefreshStream.listen((_) {
      final profile = ref.read(currentUserProfileProvider).valueOrNull;
      if (profile == null) {
        return;
      }

      unawaited(
        pushRepository.syncForUser(
          userId: profile.id,
          settings: profile.notificationSettings,
        ),
      );
    });
  }

  @override
  void dispose() {
    _profileSubscription?.close();
    _tokenRefreshSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'ReceiptNest AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
