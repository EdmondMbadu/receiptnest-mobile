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
      if (location == route) return;
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
        backgroundColor:
            isDark ? const Color(0xFF0D0D14) : const Color(0xFFF6F7F9),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Text(
            'ReceiptNest AI',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: cs.onSurface,
            ),
          ),
          actions: [
            Container(
              width: 36,
              height: 36,
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: IconButton(
                icon: Icon(
                  isDark
                      ? Icons.light_mode_rounded
                      : Icons.dark_mode_rounded,
                  size: 18,
                  color: cs.primary,
                ),
                padding: EdgeInsets.zero,
                tooltip: isDark ? 'Light mode' : 'Dark mode',
                onPressed: () =>
                    ref.read(themeModeProvider.notifier).toggle(),
              ),
            ),
            Container(
              width: 36,
              height: 36,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: cs.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: IconButton(
                icon: Icon(Icons.logout_rounded,
                    size: 18, color: cs.error),
                padding: EdgeInsets.zero,
                tooltip: 'Sign out',
                onPressed: () =>
                    ref.read(authRepositoryProvider).logout(),
              ),
            ),
          ],
        ),
        body: child,
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0D0D14) : Colors.white,
            border: Border(
              top: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.grey.shade200,
              ),
            ),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 12,
                      offset: const Offset(0, -4),
                    ),
                  ],
          ),
          child: NavigationBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            indicatorColor: cs.primary.withValues(alpha: 0.1),
            selectedIndex: currentIndex,
            labelBehavior:
                NavigationDestinationLabelBehavior.alwaysShow,
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
            destinations: [
              NavigationDestination(
                icon: Icon(Icons.home_outlined,
                    color: cs.onSurface.withValues(alpha: 0.4)),
                selectedIcon:
                    Icon(Icons.home_rounded, color: cs.primary),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.auto_awesome_outlined,
                    color: cs.onSurface.withValues(alpha: 0.4)),
                selectedIcon: Icon(Icons.auto_awesome_rounded,
                    color: cs.primary),
                label: 'Insights',
              ),
              NavigationDestination(
                icon: Icon(Icons.folder_outlined,
                    color: cs.onSurface.withValues(alpha: 0.4)),
                selectedIcon: Icon(Icons.folder_rounded,
                    color: cs.primary),
                label: 'Collections',
              ),
            ],
          ),
        ),
        drawer: Drawer(
          backgroundColor:
              isDark ? const Color(0xFF0D0D14) : Colors.white,
          child: Column(
            children: [
              // ── Premium drawer header ──
              Container(
                width: double.infinity,
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 36,
                  bottom: 28,
                  left: 24,
                  right: 24,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isDark
                        ? [
                            cs.primary.withValues(alpha: 0.12),
                            const Color(0xFF0D0D14),
                          ]
                        : [
                            cs.primary.withValues(alpha: 0.06),
                            Colors.white,
                          ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            cs.primary.withValues(alpha: 0.2),
                            cs.primary.withValues(alpha: 0.05),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color:
                                cs.primary.withValues(alpha: 0.15),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.receipt_long_rounded,
                        color: cs.primary,
                        size: 28,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      profile?.displayName ?? 'ReceiptNest AI',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: cs.onSurface,
                      ),
                    ),
                    if (profile != null &&
                        profile.email.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        profile.email,
                        style: TextStyle(
                          fontSize: 13,
                          color:
                              cs.onSurface.withValues(alpha: 0.45),
                        ),
                      ),
                    ],
                    if (profile?.isPro == true) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color:
                              cs.primary.withValues(alpha: 0.1),
                          borderRadius:
                              BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.diamond_outlined,
                                size: 14, color: cs.primary),
                            const SizedBox(width: 4),
                            Text(
                              'Pro',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: cs.primary,
                              ),
                            ),
                          ],
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
              _DrawerTile(
                icon: Icons.settings_outlined,
                label: 'Settings',
                onTap: () => openFromDrawer('/app/settings'),
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
                child: Row(
                  children: [
                    Icon(
                      Icons.receipt_long_rounded,
                      size: 16,
                      color: cs.onSurface.withValues(alpha: 0.2),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'ReceiptNest AI',
                      style: TextStyle(
                        color:
                            cs.onSurface.withValues(alpha: 0.25),
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
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
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.04)
                        : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon,
                      size: 18,
                      color:
                          cs.onSurface.withValues(alpha: 0.6)),
                ),
                const SizedBox(width: 14),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: cs.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
