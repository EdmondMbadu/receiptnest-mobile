import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/public_app_config.dart';

class SupportScreen extends ConsumerWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appConfig =
        ref.watch(publicAppConfigProvider).valueOrNull ??
        const PublicAppConfig();

    return Scaffold(
      appBar: AppBar(title: const Text('Support')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            appConfig.supportTitle,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          for (
            var index = 0;
            index < appConfig.supportParagraphs.length;
            index++
          )
            Padding(
              padding: EdgeInsets.only(
                bottom: index == appConfig.supportParagraphs.length - 1
                    ? 0
                    : 12,
              ),
              child: Text(appConfig.supportParagraphs[index]),
            ),
        ],
      ),
    );
  }
}
