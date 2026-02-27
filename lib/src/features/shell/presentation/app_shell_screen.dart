import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/data/auth_repository.dart';
import '../../../core/theme/theme_controller.dart';

class AppShellScreen extends ConsumerWidget {
  const AppShellScreen({
    super.key,
    required this.child,
    required this.location,
  });

  final Widget child;
  final String location;

  int get currentIndex {
    if (location.startsWith('/app/insights')) return 1;
    if (location.startsWith('/app/folders')) return 2;
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    final isHomeTab = currentIndex == 0;

    Future<void> openFromDrawer(String route) async {
      Navigator.of(context).pop();
      context.push(route);
    }

    return PopScope<void>(
      canPop: isHomeTab,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !isHomeTab) {
          context.go('/app/home');
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(profile?.displayName ?? 'ReceiptNest'),
          actions: [
            IconButton(
              icon: const Icon(Icons.brightness_6_outlined),
              onPressed: () => ref.read(themeModeProvider.notifier).toggle(),
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () => ref.read(authRepositoryProvider).logout(),
            ),
          ],
        ),
        body: child,
        bottomNavigationBar: NavigationBar(
          selectedIndex: currentIndex,
          onDestinationSelected: (index) {
            switch (index) {
              case 0:
                context.go('/app/home');
                break;
              case 1:
                context.go('/app/insights');
                break;
              case 2:
                context.go('/app/folders');
                break;
            }
          },
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), label: 'Insights'),
            NavigationDestination(icon: Icon(Icons.folder_outlined), label: 'Folders'),
          ],
        ),
        drawer: Drawer(
          child: SafeArea(
            child: ListView(
              children: [
                ListTile(
                  leading: const Icon(Icons.currency_exchange),
                  title: const Text('Pricing'),
                  onTap: () => openFromDrawer('/app/pricing'),
                ),
                if (profile?.isAdmin == true)
                  ListTile(
                    leading: const Icon(Icons.admin_panel_settings_outlined),
                    title: const Text('Admin'),
                    onTap: () => openFromDrawer('/app/admin'),
                  ),
                ListTile(
                  leading: const Icon(Icons.support_agent_outlined),
                  title: const Text('Support'),
                  onTap: () => openFromDrawer('/support'),
                ),
                ListTile(
                  leading: const Icon(Icons.gavel_outlined),
                  title: const Text('Terms'),
                  onTap: () => openFromDrawer('/terms'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
