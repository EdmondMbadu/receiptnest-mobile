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
          for (var index = 0; index < appConfig.termsParagraphs.length; index++)
            Padding(
              padding: EdgeInsets.only(
                bottom: index == appConfig.termsParagraphs.length - 1 ? 0 : 8,
              ),
              child: Text(appConfig.termsParagraphs[index]),
            ),
        ],
      ),
    );
  }
}
