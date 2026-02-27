import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/auth_repository.dart';

class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  bool _sending = false;
  String? _message;
  String? _error;

  Future<void> _resend() async {
    setState(() {
      _sending = true;
      _error = null;
      _message = null;
    });

    try {
      await ref.read(authRepositoryProvider).sendVerificationEmail();
      setState(() => _message = 'Verification email sent. Check your inbox.');
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify Email'),
        actions: [
          IconButton(
            onPressed: () => ref.read(authRepositoryProvider).logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Please verify your email',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'We sent a verification link to ${user?.email ?? 'your email address'}.',
                    ),
                    const SizedBox(height: 16),
                    if (_message != null)
                      Text(_message!, style: const TextStyle(color: Colors.green)),
                    if (_error != null)
                      Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _sending ? null : _resend,
                      child: Text(_sending ? 'Sending...' : 'Resend verification email'),
                    ),
                    TextButton(
                      onPressed: () => context.go('/login'),
                      child: const Text('Back to login'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
