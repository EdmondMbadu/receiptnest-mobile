import 'package:flutter/material.dart';

class BrandHeader extends StatelessWidget {
  const BrandHeader({
    super.key,
    this.subtitle,
  });

  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        const SizedBox(height: 8),
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: cs.primary.withValues(alpha: 0.18),
                blurRadius: 32,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Image.asset(
              'assets/images/receipt-nest.png',
              width: 96,
              height: 96,
              fit: BoxFit.contain,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'ReceiptNest AI',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(
            subtitle!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: cs.onSurface.withValues(alpha: 0.6),
                  height: 1.5,
                ),
          ),
        ],
      ],
    );
  }
}
