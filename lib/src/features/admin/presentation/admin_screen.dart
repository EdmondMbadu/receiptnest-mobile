import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/public_app_config.dart';
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

  final _landingSubtitleController = TextEditingController();
  final _landingFeaturePillsController = TextEditingController();
  final _supportTitleController = TextEditingController();
  final _supportParagraphsController = TextEditingController();
  final _termsTitleController = TextEditingController();
  final _termsParagraphsController = TextEditingController();
  final _pricingHeadlineController = TextEditingController();
  final _pricingSubheadlineController = TextEditingController();
  final _pricingMonthlyPriceController = TextEditingController();
  final _pricingAnnualPriceController = TextEditingController();
  final _pricingAnnualSavingsBadgeController = TextEditingController();
  final _pricingProPlanNameController = TextEditingController();
  final _pricingFreePlanNameController = TextEditingController();
  final _pricingProTaglineController = TextEditingController();
  final _pricingFreeTaglineController = TextEditingController();
  final _pricingProFeaturesController = TextEditingController();
  final _pricingFreeFeaturesController = TextEditingController();
  final _pricingTrustLabelController = TextEditingController();
  final _aiSuggestedQuestionsController = TextEditingController();
  final _uploadMaxFileSizeMbController = TextEditingController();
  final _uploadAllowedExtensionsController = TextEditingController();
  final _uploadAllowedMimeTypesController = TextEditingController();

  bool _sending = false;
  bool _savingFreePlanReceiptLimit = false;
  bool _savingPublicAppConfig = false;
  bool _publicAppConfigInitialized = false;

  String? _error;
  String? _success;
  String? _freePlanReceiptLimitError;
  String? _freePlanReceiptLimitSuccess;
  String? _publicAppConfigError;
  String? _publicAppConfigSuccess;

  @override
  void dispose() {
    _toController.dispose();
    _subjectController.dispose();
    _messageController.dispose();
    _freePlanReceiptLimitController.dispose();
    _freePlanReceiptLimitFocusNode.dispose();
    _landingSubtitleController.dispose();
    _landingFeaturePillsController.dispose();
    _supportTitleController.dispose();
    _supportParagraphsController.dispose();
    _termsTitleController.dispose();
    _termsParagraphsController.dispose();
    _pricingHeadlineController.dispose();
    _pricingSubheadlineController.dispose();
    _pricingMonthlyPriceController.dispose();
    _pricingAnnualPriceController.dispose();
    _pricingAnnualSavingsBadgeController.dispose();
    _pricingProPlanNameController.dispose();
    _pricingFreePlanNameController.dispose();
    _pricingProTaglineController.dispose();
    _pricingFreeTaglineController.dispose();
    _pricingProFeaturesController.dispose();
    _pricingFreeFeaturesController.dispose();
    _pricingTrustLabelController.dispose();
    _aiSuggestedQuestionsController.dispose();
    _uploadMaxFileSizeMbController.dispose();
    _uploadAllowedExtensionsController.dispose();
    _uploadAllowedMimeTypesController.dispose();
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

  void _initializePublicAppConfigControllers(PublicAppConfig config) {
    _landingSubtitleController.text = config.landingSubtitle;
    _landingFeaturePillsController.text = config.landingFeaturePills.join('\n');
    _supportTitleController.text = config.supportTitle;
    _supportParagraphsController.text = config.supportParagraphs.join('\n');
    _termsTitleController.text = config.termsTitle;
    _termsParagraphsController.text = config.termsParagraphs.join('\n');
    _pricingHeadlineController.text = config.pricingHeadline;
    _pricingSubheadlineController.text = config.pricingSubheadline;
    _pricingMonthlyPriceController.text = config.pricingMonthlyPrice;
    _pricingAnnualPriceController.text = config.pricingAnnualPrice;
    _pricingAnnualSavingsBadgeController.text =
        config.pricingAnnualSavingsBadge;
    _pricingProPlanNameController.text = config.pricingProPlanName;
    _pricingFreePlanNameController.text = config.pricingFreePlanName;
    _pricingProTaglineController.text = config.pricingProTagline;
    _pricingFreeTaglineController.text = config.pricingFreeTagline;
    _pricingProFeaturesController.text = config.pricingProFeatures.join('\n');
    _pricingFreeFeaturesController.text = config.pricingFreeFeatures.join('\n');
    _pricingTrustLabelController.text = config.pricingTrustLabel;
    _aiSuggestedQuestionsController.text = config.aiSuggestedQuestions.join(
      '\n',
    );
    _uploadMaxFileSizeMbController.text =
        (config.uploadMaxFileSizeBytes ~/ (1024 * 1024)).toString();
    _uploadAllowedExtensionsController.text = config.uploadAllowedExtensions
        .join(', ');
    _uploadAllowedMimeTypesController.text = config.uploadAllowedMimeTypes.join(
      '\n',
    );
    _publicAppConfigInitialized = true;
  }

  String _nonEmptyOrFallback(String value, String fallback) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? fallback : trimmed;
  }

  String _trimmedOrEmpty(String value) => value.trim();

  List<String> _newlineListOrFallback(String value, List<String> fallback) {
    final lines = value
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    return lines.isEmpty ? fallback : lines;
  }

  List<String> _csvListOrFallback(String value, List<String> fallback) {
    final items = value
        .split(',')
        .map((item) => item.trim().toLowerCase())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    return items.isEmpty ? fallback : items;
  }

  Future<void> _savePublicAppConfig() async {
    setState(() {
      _savingPublicAppConfig = true;
      _publicAppConfigError = null;
      _publicAppConfigSuccess = null;
    });

    try {
      final uploadMaxFileSizeMb = int.tryParse(
        _uploadMaxFileSizeMbController.text.trim(),
      );
      if (uploadMaxFileSizeMb == null || uploadMaxFileSizeMb < 1) {
        throw Exception('Upload max size must be a whole number above 0.');
      }

      final userId = ref.read(currentUserProvider)?.uid;
      await ref
          .read(firestoreProvider)
          .collection(publicConfigCollection)
          .doc(publicAppConfigDocId)
          .set({
            'landingSubtitle': _nonEmptyOrFallback(
              _landingSubtitleController.text,
              defaultLandingSubtitle,
            ),
            'landingFeaturePills': _newlineListOrFallback(
              _landingFeaturePillsController.text,
              defaultLandingFeaturePills,
            ),
            'supportTitle': _nonEmptyOrFallback(
              _supportTitleController.text,
              defaultSupportTitle,
            ),
            'supportParagraphs': _newlineListOrFallback(
              _supportParagraphsController.text,
              defaultSupportParagraphs,
            ),
            'termsTitle': _nonEmptyOrFallback(
              _termsTitleController.text,
              defaultTermsTitle,
            ),
            'termsParagraphs': _newlineListOrFallback(
              _termsParagraphsController.text,
              defaultTermsParagraphs,
            ),
            'pricingHeadline': _nonEmptyOrFallback(
              _pricingHeadlineController.text,
              defaultPricingHeadline,
            ),
            'pricingSubheadline': _nonEmptyOrFallback(
              _pricingSubheadlineController.text,
              defaultPricingSubheadline,
            ),
            'pricingMonthlyPrice': _nonEmptyOrFallback(
              _pricingMonthlyPriceController.text,
              defaultPricingMonthlyPrice,
            ),
            'pricingAnnualPrice': _nonEmptyOrFallback(
              _pricingAnnualPriceController.text,
              defaultPricingAnnualPrice,
            ),
            'pricingAnnualSavingsBadge': _trimmedOrEmpty(
              _pricingAnnualSavingsBadgeController.text,
            ),
            'pricingProPlanName': _nonEmptyOrFallback(
              _pricingProPlanNameController.text,
              defaultPricingProPlanName,
            ),
            'pricingFreePlanName': _nonEmptyOrFallback(
              _pricingFreePlanNameController.text,
              defaultPricingFreePlanName,
            ),
            'pricingProTagline': _nonEmptyOrFallback(
              _pricingProTaglineController.text,
              defaultPricingProTagline,
            ),
            'pricingFreeTagline': _nonEmptyOrFallback(
              _pricingFreeTaglineController.text,
              defaultPricingFreeTagline,
            ),
            'pricingProFeatures': _newlineListOrFallback(
              _pricingProFeaturesController.text,
              defaultPricingProFeatures,
            ),
            'pricingFreeFeatures': _newlineListOrFallback(
              _pricingFreeFeaturesController.text,
              defaultPricingFreeFeatures,
            ),
            'pricingTrustLabel': _nonEmptyOrFallback(
              _pricingTrustLabelController.text,
              defaultPricingTrustLabel,
            ),
            'aiSuggestedQuestions': _newlineListOrFallback(
              _aiSuggestedQuestionsController.text,
              defaultAiSuggestedQuestions,
            ),
            'uploadMaxFileSizeBytes': uploadMaxFileSizeMb * 1024 * 1024,
            'uploadAllowedExtensions': _csvListOrFallback(
              _uploadAllowedExtensionsController.text,
              defaultUploadAllowedExtensions,
            ),
            'uploadAllowedMimeTypes': _newlineListOrFallback(
              _uploadAllowedMimeTypesController.text,
              defaultUploadAllowedMimeTypes,
            ),
            'updatedAt': FieldValue.serverTimestamp(),
            'updatedBy': userId,
          }, SetOptions(merge: true));

      setState(() {
        _publicAppConfigSuccess = 'Public app content saved.';
      });
    } catch (e) {
      setState(() {
        _publicAppConfigError = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _savingPublicAppConfig = false);
      }
    }
  }

  InputDecoration _decoration({required String label, String? helper}) {
    return InputDecoration(labelText: label, helperText: helper);
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    final billingConfig = ref.watch(publicBillingConfigProvider).valueOrNull;
    final appConfigAsync = ref.watch(publicAppConfigProvider);
    final appConfig = appConfigAsync.valueOrNull ?? const PublicAppConfig();
    final freePlanReceiptLimit =
        billingConfig?.freePlanReceiptLimit ?? defaultFreePlanReceiptLimit;
    if (profile?.isAdmin != true) {
      return const Scaffold(
        body: Center(child: Text('Admin access required.')),
      );
    }

    if (appConfigAsync.hasValue && !_publicAppConfigInitialized) {
      _initializePublicAppConfigControllers(appConfig);
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
                        'Public app content',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'These fields update the public app copy and upload rules through publicConfig/appContent.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _landingSubtitleController,
                        maxLines: 3,
                        decoration: _decoration(label: 'Landing subtitle'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _landingFeaturePillsController,
                        maxLines: 3,
                        decoration: _decoration(
                          label: 'Landing feature pills',
                          helper:
                              'One pill per line. The first three are shown.',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _supportTitleController,
                        decoration: _decoration(label: 'Support title'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _supportParagraphsController,
                        maxLines: 4,
                        decoration: _decoration(
                          label: 'Support paragraphs',
                          helper: 'One paragraph per line.',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _termsTitleController,
                        decoration: _decoration(label: 'Terms title'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _termsParagraphsController,
                        maxLines: 4,
                        decoration: _decoration(
                          label: 'Terms paragraphs',
                          helper: 'One paragraph per line.',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _pricingHeadlineController,
                        decoration: _decoration(label: 'Pricing headline'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _pricingSubheadlineController,
                        maxLines: 2,
                        decoration: _decoration(label: 'Pricing subheadline'),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _pricingMonthlyPriceController,
                              decoration: _decoration(label: 'Monthly price'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _pricingAnnualPriceController,
                              decoration: _decoration(label: 'Annual price'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _pricingAnnualSavingsBadgeController,
                        decoration: _decoration(
                          label: 'Annual savings badge',
                          helper: 'Leave blank to hide the badge.',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _pricingProPlanNameController,
                              decoration: _decoration(label: 'Pro plan name'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _pricingFreePlanNameController,
                              decoration: _decoration(label: 'Free plan name'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _pricingProTaglineController,
                              decoration: _decoration(label: 'Pro tagline'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _pricingFreeTaglineController,
                              decoration: _decoration(label: 'Free tagline'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _pricingProFeaturesController,
                        maxLines: 5,
                        decoration: _decoration(
                          label: 'Pro features',
                          helper: 'One feature per line.',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _pricingFreeFeaturesController,
                        maxLines: 5,
                        decoration: _decoration(
                          label: 'Free features',
                          helper:
                              'One feature per line. Use {freePlanReceiptLimit} for the live cap.',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _pricingTrustLabelController,
                        decoration: _decoration(label: 'Pricing trust label'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _aiSuggestedQuestionsController,
                        maxLines: 6,
                        decoration: _decoration(
                          label: 'AI suggested questions',
                          helper: 'One question per line.',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _uploadMaxFileSizeMbController,
                        keyboardType: TextInputType.number,
                        decoration: _decoration(label: 'Upload max size (MB)'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _uploadAllowedExtensionsController,
                        decoration: _decoration(
                          label: 'Upload allowed extensions',
                          helper: 'Comma-separated, for example: jpg, png, pdf',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _uploadAllowedMimeTypesController,
                        maxLines: 6,
                        decoration: _decoration(
                          label: 'Upload allowed MIME types',
                          helper: 'One MIME type per line.',
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _savingPublicAppConfig
                            ? null
                            : _savePublicAppConfig,
                        child: Text(
                          _savingPublicAppConfig
                              ? 'Saving...'
                              : 'Save public app content',
                        ),
                      ),
                      if (_publicAppConfigError != null)
                        Text(
                          _publicAppConfigError!,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      if (_publicAppConfigSuccess != null)
                        Text(
                          _publicAppConfigSuccess!,
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
