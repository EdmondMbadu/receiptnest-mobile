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
      await ref
          .read(authRepositoryProvider)
          .updateProfileInfo(
            firstName: _firstNameController.text,
            lastName: _lastNameController.text,
          );
      if (!mounted) return;
      setState(() => _settingsSuccess = 'Profile saved.');
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _settingsError = _errorMessage(
          error,
          'Unable to save profile details.',
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _settingsSaving = false);
      }
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
      setState(
        () => _notificationError = _errorMessage(
          error,
          'Unable to update notification settings.',
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _notificationSaving = false);
      }
    }
  }

  Future<void> _changePassword(bool usesPasswordAuth) async {
    setState(_clearAccountMessages);

    if (!usesPasswordAuth) {
      setState(() {
        _passwordError =
            'Password updates are only available for email/password accounts.';
      });
      return;
    }

    final newPassword = _passwordNextController.text.trim();
    final confirmPassword = _passwordConfirmController.text.trim();

    if (newPassword.length < 6) {
      setState(
        () => _passwordError = 'New password must be at least 6 characters.',
      );
      return;
    }
    if (newPassword != confirmPassword) {
      setState(
        () => _passwordError = 'New password and confirmation do not match.',
      );
      return;
    }

    setState(() => _passwordSaving = true);
    try {
      await ref
          .read(authRepositoryProvider)
          .changePassword(
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
      setState(
        () =>
            _passwordError = _errorMessage(error, 'Unable to change password.'),
      );
    } finally {
      if (mounted) {
        setState(() => _passwordSaving = false);
      }
    }
  }

  Future<void> _deleteAccount(bool usesPasswordAuth) async {
    if (!_canConfirmDelete(usesPasswordAuth)) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete account?'),
          content: const Text(
            'This permanently deletes your profile, receipts, chats, folders, and shared data. This cannot be undone.',
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
        );
      },
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
      setState(
        () => _deleteError = _errorMessage(
          error,
          'Unable to delete account right now.',
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _deletePending = false);
      }
    }
  }

  Widget _statusMessage(String message, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        message,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          SegmentedButton<_SettingsTab>(
            segments: const [
              ButtonSegment<_SettingsTab>(
                value: _SettingsTab.general,
                label: Text('General'),
              ),
              ButtonSegment<_SettingsTab>(
                value: _SettingsTab.account,
                label: Text('Account'),
              ),
              ButtonSegment<_SettingsTab>(
                value: _SettingsTab.notifications,
                label: Text('Notifications'),
              ),
            ],
            selected: {_activeTab},
            showSelectedIcon: false,
            onSelectionChanged: (selection) {
              setState(() {
                _activeTab = selection.first;
                _clearGeneralMessages();
                _clearAccountMessages();
                _clearNotificationMessages();
              });
            },
          ),
          const SizedBox(height: 16),
          if (_activeTab == _SettingsTab.general) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Profile',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _firstNameController,
                      decoration: const InputDecoration(
                        labelText: 'First name',
                        hintText: 'Enter first name',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _lastNameController,
                      decoration: const InputDecoration(
                        labelText: 'Last name',
                        hintText: 'Enter last name',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _emailController,
                      readOnly: true,
                      decoration: const InputDecoration(labelText: 'Email'),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Appearance',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SegmentedButton<ThemeMode>(
                      segments: const [
                        ButtonSegment<ThemeMode>(
                          value: ThemeMode.light,
                          label: Text('Light'),
                        ),
                        ButtonSegment<ThemeMode>(
                          value: ThemeMode.dark,
                          label: Text('Dark'),
                        ),
                      ],
                      selected: {
                        themeMode == ThemeMode.light
                            ? ThemeMode.light
                            : ThemeMode.dark,
                      },
                      showSelectedIcon: false,
                      onSelectionChanged: (selection) {
                        ref
                            .read(themeModeProvider.notifier)
                            .setMode(selection.first);
                      },
                    ),
                    if (_settingsError != null)
                      _statusMessage(_settingsError!, cs.error),
                    if (_settingsSuccess != null)
                      _statusMessage(
                        _settingsSuccess!,
                        const Color(0xFF00C805),
                      ),
                    const SizedBox(height: 14),
                    FilledButton(
                      onPressed: _settingsSaving ? null : _saveGeneral,
                      child: Text(
                        _settingsSaving ? 'Saving...' : 'Save changes',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (_activeTab == _SettingsTab.notifications) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Email preferences',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Receipt processing'),
                      subtitle: const Text(
                        'Updates when receipt extraction completes.',
                      ),
                      value: _notificationSettings.receiptProcessing,
                      onChanged: (value) {
                        setState(() {
                          _notificationSettings = _notificationSettings
                              .copyWith(receiptProcessing: value);
                        });
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Product updates'),
                      subtitle: const Text(
                        'News about features and improvements.',
                      ),
                      value: _notificationSettings.productUpdates,
                      onChanged: (value) {
                        setState(() {
                          _notificationSettings = _notificationSettings
                              .copyWith(productUpdates: value);
                        });
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Security alerts'),
                      subtitle: const Text(
                        'Critical account and security notifications.',
                      ),
                      value: _notificationSettings.securityAlerts,
                      onChanged: (value) {
                        setState(() {
                          _notificationSettings = _notificationSettings
                              .copyWith(securityAlerts: value);
                        });
                      },
                    ),
                    if (_notificationError != null)
                      _statusMessage(_notificationError!, cs.error),
                    if (_notificationSuccess != null)
                      _statusMessage(
                        _notificationSuccess!,
                        const Color(0xFF00C805),
                      ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _notificationSaving
                          ? null
                          : _saveNotifications,
                      child: Text(
                        _notificationSaving ? 'Saving...' : 'Save changes',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (_activeTab == _SettingsTab.account) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Change password',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (!usesPasswordAuth)
                      Text(
                        'This account uses a social sign-in provider. Password changes are not available here.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.65),
                        ),
                      )
                    else ...[
                      TextField(
                        controller: _passwordCurrentController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Current password',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _passwordNextController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'New password',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _passwordConfirmController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Confirm password',
                        ),
                      ),
                    ],
                    if (_passwordError != null)
                      _statusMessage(_passwordError!, cs.error),
                    if (_passwordSuccess != null)
                      _statusMessage(
                        _passwordSuccess!,
                        const Color(0xFF00C805),
                      ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _passwordSaving
                          ? null
                          : () => _changePassword(usesPasswordAuth),
                      child: Text(
                        _passwordSaving ? 'Updating...' : 'Update password',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              color: cs.errorContainer.withValues(alpha: 0.25),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Delete account',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: cs.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'This permanently deletes your profile, receipts, chats, folders, shares, and linked data.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.75),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (!_showDeleteConfirmation)
                      OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _showDeleteConfirmation = true;
                            _deleteError = null;
                          });
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: cs.error,
                          side: BorderSide(
                            color: cs.error.withValues(alpha: 0.5),
                          ),
                        ),
                        child: const Text('Delete account'),
                      )
                    else ...[
                      TextField(
                        controller: _deleteConfirmController,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'Type DELETE to confirm',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      if (usesPasswordAuth) ...[
                        const SizedBox(height: 10),
                        TextField(
                          controller: _deletePasswordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Current password',
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ],
                      if (_deleteError != null)
                        _statusMessage(_deleteError!, cs.error),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: cs.error,
                                foregroundColor: cs.onError,
                              ),
                              onPressed: _canConfirmDelete(usesPasswordAuth)
                                  ? () => _deleteAccount(usesPasswordAuth)
                                  : null,
                              child: Text(
                                _deletePending
                                    ? 'Deleting...'
                                    : 'Confirm delete',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: _deletePending
                                ? null
                                : () {
                                    setState(() {
                                      _showDeleteConfirmation = false;
                                      _deleteConfirmController.clear();
                                      _deletePasswordController.clear();
                                      _deleteError = null;
                                    });
                                  },
                            child: const Text('Cancel'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
          if (profile == null && !_initializedFromProfile)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                'Loading account settings...',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
