import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/public_billing_config.dart';
import '../../auth/data/auth_repository.dart';

class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen> {
  final _toController = TextEditingController();
  final _subjectController = TextEditingController(text: 'Test Email');
  final _messageController = TextEditingController(
    text: 'This is a test email from ReceiptNest AI.',
  );
  final _freePlanReceiptLimitController = TextEditingController(
    text: defaultFreePlanReceiptLimit.toString(),
  );
  final _freePlanReceiptLimitFocusNode = FocusNode();

  bool _sending = false;
  bool _savingFreePlanReceiptLimit = false;
  String? _error;
  String? _success;
  String? _freePlanReceiptLimitError;
  String? _freePlanReceiptLimitSuccess;

  @override
  void dispose() {
    _toController.dispose();
    _subjectController.dispose();
    _messageController.dispose();
    _freePlanReceiptLimitController.dispose();
    _freePlanReceiptLimitFocusNode.dispose();
    super.dispose();
  }

  Future<void> _sendTestEmail() async {
    setState(() {
      _sending = true;
      _error = null;
      _success = null;
    });

    try {
      final callable = ref
          .read(functionsProvider)
          .httpsCallable('sendTestEmail');
      await callable.call({
        'to': _toController.text.trim(),
        'subject': _subjectController.text.trim(),
        'message': _messageController.text.trim(),
      });
      setState(() {
        _success = 'Test email sent to ${_toController.text.trim()}';
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _saveFreePlanReceiptLimit() async {
    setState(() {
      _savingFreePlanReceiptLimit = true;
      _freePlanReceiptLimitError = null;
      _freePlanReceiptLimitSuccess = null;
    });

    try {
      final parsed = int.tryParse(_freePlanReceiptLimitController.text.trim());
      if (parsed == null || parsed < 1) {
        throw Exception('Enter a whole number greater than 0.');
      }

      final userId = ref.read(currentUserProvider)?.uid;
      await ref
          .read(firestoreProvider)
          .collection(publicConfigCollection)
          .doc(publicBillingConfigDocId)
          .set({
            'freePlanReceiptLimit': parsed,
            'updatedAt': FieldValue.serverTimestamp(),
            'updatedBy': userId,
          }, SetOptions(merge: true));

      setState(() {
        _freePlanReceiptLimitSuccess = 'Free-plan receipt limit saved.';
      });
    } catch (e) {
      setState(() {
        _freePlanReceiptLimitError = e.toString().replaceFirst(
          'Exception: ',
          '',
        );
      });
    } finally {
      if (mounted) {
        setState(() => _savingFreePlanReceiptLimit = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    final billingConfig = ref.watch(publicBillingConfigProvider).valueOrNull;
    final freePlanReceiptLimit =
        billingConfig?.freePlanReceiptLimit ?? defaultFreePlanReceiptLimit;
    if (profile?.isAdmin != true) {
      return const Scaffold(
        body: Center(child: Text('Admin access required.')),
      );
    }

    if (!_freePlanReceiptLimitFocusNode.hasFocus &&
        _freePlanReceiptLimitController.text !=
            freePlanReceiptLimit.toString()) {
      _freePlanReceiptLimitController.text = freePlanReceiptLimit.toString();
    }

    final usersStream = ref
        .watch(firestoreProvider)
        .collection('users')
        .orderBy('createdAt', descending: true)
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('Admin')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: usersStream,
        builder: (context, snapshot) {
          final users = snapshot.data?.docs ?? const [];
          final proCount = users
              .where(
                (doc) => (doc.data()['subscriptionPlan'] as String?) == 'pro',
              )
              .length;
          final adminCount = users
              .where((doc) => (doc.data()['role'] as String?) == 'admin')
              .length;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      Chip(label: Text('Users: ${users.length}')),
                      Chip(label: Text('Pro: $proCount')),
                      Chip(label: Text('Admins: $adminCount')),
                    ],
                  ),
                ),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Free-plan receipt limit',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Controls the limit shown in pricing and enforced in the official app upload flow.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _freePlanReceiptLimitController,
                        focusNode: _freePlanReceiptLimitFocusNode,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Receipt cap',
                          helperText: 'Current: $freePlanReceiptLimit',
                        ),
                      ),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: _savingFreePlanReceiptLimit
                            ? null
                            : _saveFreePlanReceiptLimit,
                        child: Text(
                          _savingFreePlanReceiptLimit
                              ? 'Saving...'
                              : 'Save limit',
                        ),
                      ),
                      if (_freePlanReceiptLimitError != null)
                        Text(
                          _freePlanReceiptLimitError!,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      if (_freePlanReceiptLimitSuccess != null)
                        Text(
                          _freePlanReceiptLimitSuccess!,
                          style: const TextStyle(color: Colors.green),
                        ),
                    ],
                  ),
                ),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Send test email',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _toController,
                        decoration: const InputDecoration(
                          labelText: 'Recipient',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _subjectController,
                        decoration: const InputDecoration(labelText: 'Subject'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _messageController,
                        maxLines: 4,
                        decoration: const InputDecoration(labelText: 'Message'),
                      ),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: _sending ? null : _sendTestEmail,
                        child: Text(
                          _sending ? 'Sending...' : 'Send test email',
                        ),
                      ),
                      if (_error != null)
                        Text(
                          _error!,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      if (_success != null)
                        Text(
                          _success!,
                          style: const TextStyle(color: Colors.green),
                        ),
                    ],
                  ),
                ),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Recent users',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      if (snapshot.connectionState == ConnectionState.waiting)
                        const Center(child: CircularProgressIndicator())
                      else
                        ...users.take(100).map((doc) {
                          final data = doc.data();
                          final fullName =
                              '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'
                                  .trim();
                          final email = data['email']?.toString() ?? '';
                          final role = data['role']?.toString() ?? 'user';
                          final plan =
                              data['subscriptionPlan']?.toString() ?? 'free';

                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(fullName.isEmpty ? email : fullName),
                            subtitle: Text(email),
                            trailing: Text('$role / $plan'),
                          );
                        }),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
