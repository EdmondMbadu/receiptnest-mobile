import 'package:flutter/material.dart';

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Support')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: const [
          Text(
            'Need help?',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 12),
          Text('For account, billing, or receipt processing issues, contact support at info@receipt-nest.com.'),
          SizedBox(height: 12),
          Text('Include your account email and a short issue summary so we can help quickly.'),
        ],
      ),
    );
  }
}
