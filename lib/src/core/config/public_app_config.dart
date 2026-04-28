import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/data/auth_repository.dart';
import 'public_billing_config.dart';

const publicAppConfigDocId = 'appContent';

const defaultLandingSubtitle =
    'Receipt inbox for freelancers and small teams.\nTrack, review, and export expenses with AI assistance.';
const defaultLandingFeaturePills = <String>[
  'AI-powered',
  'Secure',
  'Cloud sync',
];

const defaultSupportTitle = 'Need help?';
const defaultSupportParagraphs = <String>[
  'For account, billing, or receipt processing issues, contact support at info@receipt-nest.com.',
  'Include your account email and a short issue summary so we can help quickly.',
];

const defaultTermsTitle = 'ReceiptNest AI Terms';
const defaultTermsParagraphs = <String>[
  'By using ReceiptNest AI, you agree to process only receipts you are authorized to store and analyze.',
  'Subscription billing is managed by the payment provider available on your platform and renews according to your selected plan.',
  'For the latest legal terms, refer to receipt-nest web terms page.',
];

const defaultPricingHeadline = 'Choose your plan';
const defaultPricingSubheadline =
    'Upgrade to Pro for unlimited access and faster workflows';
const defaultPricingMonthlyPrice = r'$9';
const defaultPricingAnnualPrice = r'$100';
const defaultPricingAnnualSavingsBadge = 'Save 7%';
const defaultPricingProPlanName = 'Pro';
const defaultPricingFreePlanName = 'Free';
const legacyPricingProTagline = 'For power users';
const defaultPricingProTagline =
    'Everything in Free, plus unlimited receipts, deeper insights, and richer exports.';
const defaultPricingFreeTagline = 'For getting started';
const legacyPricingProFeatures = <String>[
  'Unlimited receipts',
  'Advanced search & filters',
  'CSV and PDF exports',
  'Priority support',
];
const defaultPricingProFeatures = <String>[
  'Unlimited receipts',
  'Advanced search & filters',
  'Export to CSV + PDF',
  'Spending insights & trends',
  'Priority support',
  'Early access to new features',
];
const defaultPricingFreeFeatures = <String>[
  'Up to {freePlanReceiptLimit} receipts',
  'Smart auto-tagging',
  'Email & PDF uploads',
  'Single workspace',
];
const defaultPricingTrustLabel = 'Secure billing';

const defaultAiSuggestedQuestions = <String>[
  'How can I reduce my spending this month?',
  'What are my biggest expense categories?',
  'Am I spending more than last month?',
  'Where should I cut back to save money?',
  'What patterns do you see in my spending?',
  'How much am I spending on dining out?',
];

const defaultUploadMaxFileSizeBytes = 10 * 1024 * 1024;
const defaultUploadAllowedMimeTypes = <String>[
  'image/jpeg',
  'image/jpg',
  'image/png',
  'image/webp',
  'image/heic',
  'image/heif',
  'application/pdf',
  'application/msword',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
];
const defaultUploadAllowedExtensions = <String>[
  'jpg',
  'jpeg',
  'png',
  'webp',
  'heic',
  'heif',
  'pdf',
  'doc',
  'docx',
];

String _parseString(Map<String, dynamic>? data, String key, String fallback) {
  final value = data?[key]?.toString().trim();
  if (value == null || value.isEmpty) {
    return fallback;
  }
  return value;
}

List<String> _parseStringList(
  Map<String, dynamic>? data,
  String key,
  List<String> fallback, {
  bool lowercase = false,
}) {
  final raw = data?[key];
  if (raw is! List) {
    return fallback;
  }

  final values = raw
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .map((item) => lowercase ? item.toLowerCase() : item)
      .toList(growable: false);

  if (values.isEmpty) {
    return fallback;
  }
  return values;
}

int _parsePositiveInt(Map<String, dynamic>? data, String key, int fallback) {
  final raw = data?[key];
  final parsed = switch (raw) {
    int value => value,
    double value => value.toInt(),
    String value => int.tryParse(value.trim()),
    _ => null,
  };

  if (parsed == null || parsed < 1) {
    return fallback;
  }
  return parsed;
}

String _normalizePricingProTagline(String value) {
  return value == legacyPricingProTagline ? defaultPricingProTagline : value;
}

List<String> _normalizePricingProFeatures(List<String> values) {
  if (values.length != legacyPricingProFeatures.length) {
    return values;
  }

  for (var index = 0; index < values.length; index++) {
    if (values[index] != legacyPricingProFeatures[index]) {
      return values;
    }
  }

  return defaultPricingProFeatures;
}

class PublicAppConfig {
  const PublicAppConfig({
    this.landingSubtitle = defaultLandingSubtitle,
    this.landingFeaturePills = defaultLandingFeaturePills,
    this.supportTitle = defaultSupportTitle,
    this.supportParagraphs = defaultSupportParagraphs,
    this.termsTitle = defaultTermsTitle,
    this.termsParagraphs = defaultTermsParagraphs,
    this.pricingHeadline = defaultPricingHeadline,
    this.pricingSubheadline = defaultPricingSubheadline,
    this.pricingMonthlyPrice = defaultPricingMonthlyPrice,
    this.pricingAnnualPrice = defaultPricingAnnualPrice,
    this.pricingAnnualSavingsBadge = defaultPricingAnnualSavingsBadge,
    this.pricingProPlanName = defaultPricingProPlanName,
    this.pricingFreePlanName = defaultPricingFreePlanName,
    this.pricingProTagline = defaultPricingProTagline,
    this.pricingFreeTagline = defaultPricingFreeTagline,
    this.pricingProFeatures = defaultPricingProFeatures,
    this.pricingFreeFeatures = defaultPricingFreeFeatures,
    this.pricingTrustLabel = defaultPricingTrustLabel,
    this.aiSuggestedQuestions = defaultAiSuggestedQuestions,
    this.uploadMaxFileSizeBytes = defaultUploadMaxFileSizeBytes,
    this.uploadAllowedExtensions = defaultUploadAllowedExtensions,
    this.uploadAllowedMimeTypes = defaultUploadAllowedMimeTypes,
  });

  final String landingSubtitle;
  final List<String> landingFeaturePills;
  final String supportTitle;
  final List<String> supportParagraphs;
  final String termsTitle;
  final List<String> termsParagraphs;
  final String pricingHeadline;
  final String pricingSubheadline;
  final String pricingMonthlyPrice;
  final String pricingAnnualPrice;
  final String pricingAnnualSavingsBadge;
  final String pricingProPlanName;
  final String pricingFreePlanName;
  final String pricingProTagline;
  final String pricingFreeTagline;
  final List<String> pricingProFeatures;
  final List<String> pricingFreeFeatures;
  final String pricingTrustLabel;
  final List<String> aiSuggestedQuestions;
  final int uploadMaxFileSizeBytes;
  final List<String> uploadAllowedExtensions;
  final List<String> uploadAllowedMimeTypes;

  factory PublicAppConfig.fromMap(Map<String, dynamic>? data) {
    return PublicAppConfig(
      landingSubtitle: _parseString(
        data,
        'landingSubtitle',
        defaultLandingSubtitle,
      ),
      landingFeaturePills: _parseStringList(
        data,
        'landingFeaturePills',
        defaultLandingFeaturePills,
      ),
      supportTitle: _parseString(data, 'supportTitle', defaultSupportTitle),
      supportParagraphs: _parseStringList(
        data,
        'supportParagraphs',
        defaultSupportParagraphs,
      ),
      termsTitle: _parseString(data, 'termsTitle', defaultTermsTitle),
      termsParagraphs: _parseStringList(
        data,
        'termsParagraphs',
        defaultTermsParagraphs,
      ),
      pricingHeadline: _parseString(
        data,
        'pricingHeadline',
        defaultPricingHeadline,
      ),
      pricingSubheadline: _parseString(
        data,
        'pricingSubheadline',
        defaultPricingSubheadline,
      ),
      pricingMonthlyPrice: _parseString(
        data,
        'pricingMonthlyPrice',
        defaultPricingMonthlyPrice,
      ),
      pricingAnnualPrice: _parseString(
        data,
        'pricingAnnualPrice',
        defaultPricingAnnualPrice,
      ),
      pricingAnnualSavingsBadge: _parseString(
        data,
        'pricingAnnualSavingsBadge',
        defaultPricingAnnualSavingsBadge,
      ),
      pricingProPlanName: _parseString(
        data,
        'pricingProPlanName',
        defaultPricingProPlanName,
      ),
      pricingFreePlanName: _parseString(
        data,
        'pricingFreePlanName',
        defaultPricingFreePlanName,
      ),
      pricingProTagline: _normalizePricingProTagline(
        _parseString(data, 'pricingProTagline', defaultPricingProTagline),
      ),
      pricingFreeTagline: _parseString(
        data,
        'pricingFreeTagline',
        defaultPricingFreeTagline,
      ),
      pricingProFeatures: _normalizePricingProFeatures(
        _parseStringList(data, 'pricingProFeatures', defaultPricingProFeatures),
      ),
      pricingFreeFeatures: _parseStringList(
        data,
        'pricingFreeFeatures',
        defaultPricingFreeFeatures,
      ),
      pricingTrustLabel: _parseString(
        data,
        'pricingTrustLabel',
        defaultPricingTrustLabel,
      ),
      aiSuggestedQuestions: _parseStringList(
        data,
        'aiSuggestedQuestions',
        defaultAiSuggestedQuestions,
      ),
      uploadMaxFileSizeBytes: _parsePositiveInt(
        data,
        'uploadMaxFileSizeBytes',
        defaultUploadMaxFileSizeBytes,
      ),
      uploadAllowedExtensions: _parseStringList(
        data,
        'uploadAllowedExtensions',
        defaultUploadAllowedExtensions,
        lowercase: true,
      ),
      uploadAllowedMimeTypes: _parseStringList(
        data,
        'uploadAllowedMimeTypes',
        defaultUploadAllowedMimeTypes,
        lowercase: true,
      ),
    );
  }
}

final publicAppConfigProvider = StreamProvider<PublicAppConfig>((ref) {
  final db = ref.watch(firestoreProvider);
  return db
      .collection(publicConfigCollection)
      .doc(publicAppConfigDocId)
      .snapshots()
      .map((snapshot) => PublicAppConfig.fromMap(snapshot.data()));
});

Future<PublicAppConfig> fetchPublicAppConfig(FirebaseFirestore db) async {
  final snapshot = await db
      .collection(publicConfigCollection)
      .doc(publicAppConfigDocId)
      .get();
  return PublicAppConfig.fromMap(snapshot.data());
}
