import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/theme_controller.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/models/user_profile.dart';

enum _SettingsTab { general, account, notifications }

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  static const _deleteKeyword = 'DELETE';

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordCurrentController = TextEditingController();
  final _passwordNextController = TextEditingController();
  final _passwordConfirmController = TextEditingController();
  final _deleteConfirmController = TextEditingController();
  final _deletePasswordController = TextEditingController();

  _SettingsTab _activeTab = _SettingsTab.general;
  NotificationSettings _notificationSettings = NotificationSettings.defaults;
  bool _initializedFromProfile = false;
  bool _showDeleteConfirmation = false;

  bool _settingsSaving = false;
  bool _passwordSaving = false;
  bool _notificationSaving = false;
  bool _deletePending = false;

  String? _settingsError;
  String? _settingsSuccess;
  String? _passwordError;
  String? _passwordSuccess;
  String? _notificationError;
  String? _notificationSuccess;
  String? _deleteError;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordCurrentController.dispose();
    _passwordNextController.dispose();
    _passwordConfirmController.dispose();
    _deleteConfirmController.dispose();
    _deletePasswordController.dispose();
    super.dispose();
  }

  bool _canConfirmDelete(bool usesPasswordAuth) {
    final keywordMatches =
        _deleteConfirmController.text.trim().toUpperCase() == _deleteKeyword;
    final hasPassword =
        !usesPasswordAuth || _deletePasswordController.text.trim().isNotEmpty;
    return keywordMatches && hasPassword && !_deletePending;
  }

  String _errorMessage(Object error, String fallback) {
    if (error is AppAuthException) {
      final code = error.code;
      if (code.contains('wrong-password') ||
          code.contains('invalid-credential')) {
        return 'Current password is incorrect.';
      }
      if (code.contains('too-many-requests')) {
        return 'Too many attempts. Please wait a moment and try again.';
      }
      if (error.message.trim().isNotEmpty) {
        return error.message;
      }
    }
    final raw = error.toString();
    if (raw.contains('wrong-password') || raw.contains('invalid-credential')) {
      return 'Current password is incorrect.';
    }
    if (raw.contains('too-many-requests')) {
      return 'Too many attempts. Please wait a moment and try again.';
    }
    return fallback;
  }

  void _clearGeneralMessages() {
    _settingsError = null;
    _settingsSuccess = null;
  }

  void _clearAccountMessages() {
    _passwordError = null;
    _passwordSuccess = null;
    _deleteError = null;
  }

  void _clearNotificationMessages() {
    _notificationError = null;
    _notificationSuccess = null;
  }

  Future<void> _saveGeneral() async {
    setState(() {
      _settingsSaving = true;
      _clearGeneralMessages();
    });
    try {
      await ref.read(authRepositoryProvider).updateProfileInfo(
            firstName: _firstNameController.text,
            lastName: _lastNameController.text,
          );
      if (!mounted) return;
      setState(() => _settingsSuccess = 'Profile saved.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _settingsError =
          _errorMessage(error, 'Unable to save profile details.'));
    } finally {
      if (mounted) setState(() => _settingsSaving = false);
    }
  }

  Future<void> _saveNotifications() async {
    setState(() {
      _notificationSaving = true;
      _clearNotificationMessages();
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .updateNotificationSettings(_notificationSettings);
      if (!mounted) return;
      setState(() => _notificationSuccess = 'Notification settings updated.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _notificationError =
          _errorMessage(error, 'Unable to update notification settings.'));
    } finally {
      if (mounted) setState(() => _notificationSaving = false);
    }
  }

  Future<void> _changePassword(bool usesPasswordAuth) async {
    setState(_clearAccountMessages);
    if (!usesPasswordAuth) {
      setState(() => _passwordError =
          'Password updates are only available for email/password accounts.');
      return;
    }
    final newPassword = _passwordNextController.text.trim();
    final confirmPassword = _passwordConfirmController.text.trim();
    if (newPassword.length < 6) {
      setState(() =>
          _passwordError = 'New password must be at least 6 characters.');
      return;
    }
    if (newPassword != confirmPassword) {
      setState(() =>
          _passwordError = 'New password and confirmation do not match.');
      return;
    }
    setState(() => _passwordSaving = true);
    try {
      await ref.read(authRepositoryProvider).changePassword(
            currentPassword: _passwordCurrentController.text,
            newPassword: newPassword,
          );
      if (!mounted) return;
      setState(() {
        _passwordCurrentController.clear();
        _passwordNextController.clear();
        _passwordConfirmController.clear();
        _passwordSuccess = 'Password changed successfully.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() =>
          _passwordError = _errorMessage(error, 'Unable to change password.'));
    } finally {
      if (mounted) setState(() => _passwordSaving = false);
    }
  }

  Future<void> _deleteAccount(bool usesPasswordAuth) async {
    if (!_canConfirmDelete(usesPasswordAuth)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'This permanently deletes your profile, receipts, chats, collections, and shared data. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _deletePending = true;
      _deleteError = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .deleteAccount(currentPassword: _deletePasswordController.text);
      if (!mounted) return;
      context.go('/login');
    } catch (error) {
      if (!mounted) return;
      setState(() => _deleteError =
          _errorMessage(error, 'Unable to delete account right now.'));
    } finally {
      if (mounted) setState(() => _deletePending = false);
    }
  }

  Widget _statusBanner(String message, Color color, IconData icon) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500, color: color)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final authRepo = ref.watch(authRepositoryProvider);
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    final themeMode = ref.watch(themeModeProvider);
    final usesPasswordAuth = authRepo.isCurrentUserPasswordAuth();

    if (!_initializedFromProfile && profile != null) {
      _firstNameController.text = profile.firstName;
      _lastNameController.text = profile.lastName;
      _emailController.text = profile.email;
      _notificationSettings = authRepo.getDefaultNotificationSettings(profile);
      _initializedFromProfile = true;
    }

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0D0D14) : const Color(0xFFF6F7F9),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          // ── Tab toggle ──
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.grey.shade200,
              ),
            ),
            child: Row(
              children: _SettingsTab.values.map((tab) {
                final selected = tab == _activeTab;
                final label = switch (tab) {
                  _SettingsTab.general => 'General',
                  _SettingsTab.account => 'Account',
                  _SettingsTab.notifications => 'Alerts',
                };
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _activeTab = tab;
                      _clearGeneralMessages();
                      _clearAccountMessages();
                      _clearNotificationMessages();
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: selected
                            ? (isDark
                                ? Colors.white.withValues(alpha: 0.12)
                                : Colors.white)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: selected
                            ? [
                                BoxShadow(
                                  color: Colors.black.withValues(
                                      alpha: isDark ? 0.3 : 0.06),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: Center(
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w500,
                            color: selected
                                ? cs.onSurface
                                : cs.onSurface.withValues(alpha: 0.45),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 24),

          // ── General ──
          if (_activeTab == _SettingsTab.general) ...[
            _SettingsSection(
              title: 'Profile',
              icon: Icons.person_outline_rounded,
              isDark: isDark,
              children: [
                Row(children: [
                  Expanded(
                      child: TextField(
                          controller: _firstNameController,
                          decoration: const InputDecoration(
                              labelText: 'First name'))),
                  const SizedBox(width: 12),
                  Expanded(
                      child: TextField(
                          controller: _lastNameController,
                          decoration:
                              const InputDecoration(labelText: 'Last name'))),
                ]),
                const SizedBox(height: 14),
                TextField(
                  controller: _emailController,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    suffixIcon: Icon(Icons.lock_outline_rounded,
                        size: 16,
                        color: cs.onSurface.withValues(alpha: 0.25)),
                  ),
                ),
                if (_settingsError != null)
                  _statusBanner(_settingsError!, cs.error,
                      Icons.error_outline_rounded),
                if (_settingsSuccess != null)
                  _statusBanner(_settingsSuccess!, const Color(0xFF00C805),
                      Icons.check_circle_outline_rounded),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: FilledButton(
                    onPressed: _settingsSaving ? null : _saveGeneral,
                    style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
                    child:
                        Text(_settingsSaving ? 'Saving...' : 'Save changes'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SettingsSection(
              title: 'Appearance',
              icon: Icons.palette_outlined,
              isDark: isDark,
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : cs.surfaceContainerHighest.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(children: [
                    _ThemeOption(
                      icon: Icons.light_mode_rounded,
                      label: 'Light',
                      selected: themeMode == ThemeMode.light,
                      isDark: isDark,
                      onTap: () => ref
                          .read(themeModeProvider.notifier)
                          .setMode(ThemeMode.light),
                    ),
                    const SizedBox(width: 4),
                    _ThemeOption(
                      icon: Icons.dark_mode_rounded,
                      label: 'Dark',
                      selected: themeMode == ThemeMode.dark,
                      isDark: isDark,
                      onTap: () => ref
                          .read(themeModeProvider.notifier)
                          .setMode(ThemeMode.dark),
                    ),
                  ]),
                ),
              ],
            ),
          ],

          // ── Notifications ──
          if (_activeTab == _SettingsTab.notifications) ...[
            _SettingsSection(
              title: 'Email preferences',
              icon: Icons.notifications_outlined,
              isDark: isDark,
              children: [
                _NotifTile(
                    title: 'Receipt processing',
                    subtitle: 'Updates when extraction completes',
                    value: _notificationSettings.receiptProcessing,
                    onChanged: (v) => setState(() => _notificationSettings =
                        _notificationSettings.copyWith(
                            receiptProcessing: v))),
                _NotifTile(
                    title: 'Product updates',
                    subtitle: 'News about features and improvements',
                    value: _notificationSettings.productUpdates,
                    onChanged: (v) => setState(() => _notificationSettings =
                        _notificationSettings.copyWith(productUpdates: v))),
                _NotifTile(
                    title: 'Security alerts',
                    subtitle: 'Critical account notifications',
                    value: _notificationSettings.securityAlerts,
                    onChanged: (v) => setState(() => _notificationSettings =
                        _notificationSettings.copyWith(
                            securityAlerts: v))),
                if (_notificationError != null)
                  _statusBanner(_notificationError!, cs.error,
                      Icons.error_outline_rounded),
                if (_notificationSuccess != null)
                  _statusBanner(_notificationSuccess!, const Color(0xFF00C805),
                      Icons.check_circle_outline_rounded),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: FilledButton(
                    onPressed:
                        _notificationSaving ? null : _saveNotifications,
                    style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
                    child: Text(
                        _notificationSaving ? 'Saving...' : 'Save changes'),
                  ),
                ),
              ],
            ),
          ],

          // ── Account ──
          if (_activeTab == _SettingsTab.account) ...[
            _SettingsSection(
              title: 'Change password',
              icon: Icons.lock_outline_rounded,
              isDark: isDark,
              children: [
                if (!usesPasswordAuth)
                  Text(
                    'This account uses a social sign-in provider. Password changes are not available here.',
                    style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurface.withValues(alpha: 0.5)),
                  )
                else ...[
                  TextField(
                      controller: _passwordCurrentController,
                      obscureText: true,
                      decoration: const InputDecoration(
                          labelText: 'Current password')),
                  const SizedBox(height: 12),
                  TextField(
                      controller: _passwordNextController,
                      obscureText: true,
                      decoration:
                          const InputDecoration(labelText: 'New password')),
                  const SizedBox(height: 12),
                  TextField(
                      controller: _passwordConfirmController,
                      obscureText: true,
                      decoration: const InputDecoration(
                          labelText: 'Confirm password')),
                ],
                if (_passwordError != null)
                  _statusBanner(
                      _passwordError!, cs.error, Icons.error_outline_rounded),
                if (_passwordSuccess != null)
                  _statusBanner(_passwordSuccess!, const Color(0xFF00C805),
                      Icons.check_circle_outline_rounded),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: FilledButton(
                    onPressed: _passwordSaving
                        ? null
                        : () => _changePassword(usesPasswordAuth),
                    style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
                    child: Text(
                        _passwordSaving ? 'Updating...' : 'Update password'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Danger zone
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: cs.error.withValues(alpha: isDark ? 0.08 : 0.04),
                border: Border.all(color: cs.error.withValues(alpha: 0.15)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 20, color: cs.error),
                    const SizedBox(width: 10),
                    Text('Danger zone',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: cs.error)),
                  ]),
                  const SizedBox(height: 10),
                  Text(
                    'Permanently deletes your profile, receipts, chats, collections, shares, and linked data.',
                    style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurface.withValues(alpha: 0.6)),
                  ),
                  const SizedBox(height: 14),
                  if (!_showDeleteConfirmation)
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: OutlinedButton(
                        onPressed: () => setState(() {
                          _showDeleteConfirmation = true;
                          _deleteError = null;
                        }),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: cs.error,
                          side: BorderSide(
                              color: cs.error.withValues(alpha: 0.4)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Delete account'),
                      ),
                    )
                  else ...[
                    TextField(
                      controller: _deleteConfirmController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                          labelText: 'Type DELETE to confirm'),
                      onChanged: (_) => setState(() {}),
                    ),
                    if (usesPasswordAuth) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _deletePasswordController,
                        obscureText: true,
                        decoration: const InputDecoration(
                            labelText: 'Current password'),
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                    if (_deleteError != null)
                      _statusBanner(_deleteError!, cs.error,
                          Icons.error_outline_rounded),
                    const SizedBox(height: 14),
                    Row(children: [
                      Expanded(
                        child: SizedBox(
                          height: 44,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: cs.error,
                              foregroundColor: cs.onError,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: _canConfirmDelete(usesPasswordAuth)
                                ? () => _deleteAccount(usesPasswordAuth)
                                : null,
                            child: Text(_deletePending
                                ? 'Deleting...'
                                : 'Confirm delete'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: _deletePending
                            ? null
                            : () => setState(() {
                                  _showDeleteConfirmation = false;
                                  _deleteConfirmController.clear();
                                  _deletePasswordController.clear();
                                  _deleteError = null;
                                }),
                        child: const Text('Cancel'),
                      ),
                    ]),
                  ],
                ],
              ),
            ),
          ],
          if (profile == null && !_initializedFromProfile)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Center(
                child: Text('Loading account settings...',
                    style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurface.withValues(alpha: 0.4))),
              ),
            ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.icon,
    required this.isDark,
    required this.children,
  });
  final String title;
  final IconData icon;
  final bool isDark;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: isDark ? const Color(0xFF151520) : Colors.white,
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: cs.primary),
            ),
            const SizedBox(width: 12),
            Text(title,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    color: cs.onSurface)),
          ]),
          const SizedBox(height: 18),
          ...children,
        ],
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.icon,
    required this.label,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? (isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color:
                          Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 18,
                  color: selected
                      ? cs.onSurface
                      : cs.onSurface.withValues(alpha: 0.35)),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected
                          ? cs.onSurface
                          : cs.onSurface.withValues(alpha: 0.45))),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotifTile extends StatelessWidget {
  const _NotifTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title,
            style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: cs.onSurface)),
        subtitle: Text(subtitle,
            style: TextStyle(
                fontSize: 12.5,
                color: cs.onSurface.withValues(alpha: 0.45))),
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}
