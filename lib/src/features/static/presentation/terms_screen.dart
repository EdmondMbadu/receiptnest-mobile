import 'package:flutter/material.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Terms & Conditions')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: const [
          Text(
            'ReceiptNest AI Terms',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 12),
          Text('By using ReceiptNest AI, you agree to process only receipts you are authorized to store and analyze.'),
          SizedBox(height: 8),
          Text('Subscription billing is managed by Stripe and renews according to your selected plan.'),
          SizedBox(height: 8),
          Text('For the latest legal terms, refer to receipt-nest web terms page.'),
        ],
      ),
    );
  }
}
