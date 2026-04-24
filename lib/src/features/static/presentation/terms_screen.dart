import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/public_app_config.dart';

class TermsScreen extends ConsumerWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appConfig =
        ref.watch(publicAppConfigProvider).valueOrNull ??
        const PublicAppConfig();
    final termsParagraphs = _platformTermsParagraphs(appConfig);

    return Scaffold(
      appBar: AppBar(title: const Text('Terms & Conditions')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            appConfig.termsTitle,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          for (var index = 0; index < termsParagraphs.length; index++)
            Padding(
              padding: EdgeInsets.only(
                bottom: index == termsParagraphs.length - 1 ? 0 : 8,
              ),
              child: Text(termsParagraphs[index]),
            ),
        ],
      ),
    );
  }

  List<String> _platformTermsParagraphs(PublicAppConfig appConfig) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return appConfig.termsParagraphs;
    }

    return appConfig.termsParagraphs
        .map(
          (paragraph) => paragraph.contains('Stripe')
              ? 'Subscriptions purchased in this iOS app are billed by Apple through the App Store and renew according to your selected plan.'
              : paragraph,
        )
        .toList(growable: false);
  }
}
