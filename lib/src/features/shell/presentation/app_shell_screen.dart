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
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
          title: Text(profile?.displayName ?? 'ReceiptNest AI'),
          actions: [
            IconButton(
              icon: Icon(
                isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                size: 22,
              ),
              tooltip: isDark ? 'Light mode' : 'Dark mode',
              onPressed: () => ref.read(themeModeProvider.notifier).toggle(),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.logout_rounded, size: 22),
              tooltip: 'Sign out',
              onPressed: () => ref.read(authRepositoryProvider).logout(),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: child,
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.grey.shade200,
              ),
            ),
          ),
          child: NavigationBar(
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
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.auto_awesome_outlined),
                selectedIcon: Icon(Icons.auto_awesome_rounded),
                label: 'Insights',
              ),
              NavigationDestination(
                icon: Icon(Icons.folder_outlined),
                selectedIcon: Icon(Icons.folder_rounded),
                label: 'Folders',
              ),
            ],
          ),
        ),
        drawer: Drawer(
          child: Column(
            children: [
              // Premium drawer header
              Container(
                width: double.infinity,
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 32,
                  bottom: 24,
                  left: 24,
                  right: 24,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isDark
                        ? [
                            cs.primary.withValues(alpha: 0.15),
                            cs.surface,
                          ]
                        : [
                            cs.primary.withValues(alpha: 0.08),
                            cs.surface,
                          ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.receipt_long_rounded,
                        color: cs.primary,
                        size: 28,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      profile?.displayName ?? 'ReceiptNest AI',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (profile != null && profile.email.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        profile.email,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.onSurface.withValues(alpha: 0.6),
                            ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _DrawerTile(
                icon: Icons.diamond_outlined,
                label: 'Pricing',
                onTap: () => openFromDrawer('/app/pricing'),
              ),
              if (profile?.isAdmin == true)
                _DrawerTile(
                  icon: Icons.admin_panel_settings_outlined,
                  label: 'Admin',
                  onTap: () => openFromDrawer('/app/admin'),
                ),
              _DrawerTile(
                icon: Icons.support_agent_outlined,
                label: 'Support',
                onTap: () => openFromDrawer('/support'),
              ),
              _DrawerTile(
                icon: Icons.gavel_outlined,
                label: 'Terms',
                onTap: () => openFromDrawer('/terms'),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'ReceiptNest AI',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.3),
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DrawerTile extends StatelessWidget {
  const _DrawerTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: ListTile(
        leading: Icon(icon, size: 22),
        title: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        onTap: onTap,
      ),
    );
  }
}
