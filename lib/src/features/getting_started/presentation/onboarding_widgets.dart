import 'package:flutter/material.dart';

const onboardingInk = Color(0xFF123B36);
const onboardingTeal = Color(0xFF0F766E);

class OnboardingCanvas extends StatelessWidget {
  const OnboardingCanvas({
    super.key,
    required this.child,
    this.neutral = false,
  });
  final Widget child;
  final bool neutral;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: neutral
          ? (Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF0D0D12)
                : Colors.white)
          : null,
      gradient: neutral
          ? null
          : LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: Theme.of(context).brightness == Brightness.dark
                  ? const [
                      Color(0xFF102722),
                      Color(0xFF0D1516),
                      Color(0xFF10191C),
                    ]
                  : const [
                      Color(0xFFECF6EF),
                      Color(0xFFF9FAF5),
                      Color(0xFFF1F7F7),
                    ],
            ),
    ),
    child: child,
  );
}

class OnboardingReveal extends StatelessWidget {
  const OnboardingReveal({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 550),
    curve: Curves.easeOutCubic,
    builder: (context, value, child) => Opacity(
      opacity: value,
      child: Transform.translate(
        offset: Offset(0, 16 * (1 - value)),
        child: child,
      ),
    ),
    child: child,
  );
}

class OnboardingBrand extends StatelessWidget {
  const OnboardingBrand({super.key});
  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: Image.asset(
            'assets/images/receipt-nest.png',
            width: 38,
            height: 38,
          ),
        ),
        const SizedBox(width: 10),
        const Text(
          'ReceiptNest',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
          ),
        ),
      ],
    ),
  );
}

class OnboardingProgress extends StatelessWidget {
  const OnboardingProgress({super.key, required this.stage});
  final int stage;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      label:
          'Step ${stage + 1} of 3: ${const ['Add', 'Organize', 'View'][stage]}',
      child: ExcludeSemantics(
        child: Row(
          children: [
            for (var index = 0; index < 3; index++) ...[
              if (index > 0) const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedContainer(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 300),
                      height: 4,
                      decoration: BoxDecoration(
                        color: index <= stage
                            ? cs.primary
                            : cs.primary.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      '${index + 1}  ${const ['Add', 'Organize', 'View'][index]}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: index == stage
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: index <= stage
                            ? cs.primary
                            : cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class OnboardingPaper extends StatelessWidget {
  const OnboardingPaper({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.neutral = false,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool neutral;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: dark
            ? (neutral ? const Color(0xFF16161F) : const Color(0xFF182622))
            : Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: neutral
              ? Theme.of(
                  context,
                ).colorScheme.outlineVariant.withValues(alpha: 0.5)
              : dark
              ? const Color(0xFF294039)
              : const Color(0xFFE0E9E2),
        ),
        boxShadow: neutral
            ? const []
            : [
                BoxShadow(
                  color: onboardingInk.withValues(alpha: dark ? 0.08 : 0.055),
                  blurRadius: 40,
                  offset: const Offset(0, 12),
                ),
              ],
      ),
      child: child,
    );
  }
}

/// This illustration is never inserted into the user's receipt collection.
class ReceiptIllustration extends StatelessWidget {
  const ReceiptIllustration({super.key, this.compact = false});
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = dark ? const Color(0xFF92D9B7) : onboardingTeal;
    return ExcludeSemantics(
      child: SizedBox(
        height: compact ? 136 : 254,
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: 330,
            height: 254,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 230,
                  height: 230,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(
                          0xFFC7E7D7,
                        ).withValues(alpha: dark ? 0.18 : 0.8),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 34,
                  top: 24,
                  child: Transform.rotate(
                    angle: -0.12,
                    child: Container(
                      width: 153,
                      height: 195,
                      padding: const EdgeInsets.all(19),
                      decoration: BoxDecoration(
                        color: dark
                            ? const Color(0xFF29423B)
                            : const Color(0xFFE0EBE1),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.receipt_long_outlined,
                            size: 25,
                            color: dark
                                ? Colors.white54
                                : onboardingInk.withValues(alpha: 0.4),
                          ),
                          const SizedBox(height: 20),
                          for (final width in [100.0, 74.0, 100.0, 88.0]) ...[
                            Container(
                              width: width,
                              height: 5,
                              decoration: BoxDecoration(
                                color: dark
                                    ? Colors.white12
                                    : const Color(0xFFB5C9BD),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            const SizedBox(height: 13),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 24,
                  top: 20,
                  child: Transform.rotate(
                    angle: 0.055,
                    child: Container(
                      width: 191,
                      padding: const EdgeInsets.all(21),
                      decoration: BoxDecoration(
                        color: dark ? const Color(0xFF20332C) : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: dark
                              ? const Color(0xFF3B5649)
                              : const Color(0xFFDDE8DF),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: onboardingInk.withValues(alpha: 0.12),
                            blurRadius: 26,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFECF5EC),
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                child: const Icon(
                                  Icons.local_cafe_outlined,
                                  size: 20,
                                  color: onboardingTeal,
                                ),
                              ),
                              const Spacer(),
                              const Icon(
                                Icons.check_circle_rounded,
                                color: onboardingTeal,
                                size: 21,
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'Your local café',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            '\$12.50',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1.2,
                            ),
                          ),
                          const SizedBox(height: 15),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Food & dining',
                              style: TextStyle(
                                fontSize: 10,
                                color: accent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 44,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: onboardingTeal,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: onboardingTeal.withValues(alpha: 0.18),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.auto_awesome_rounded,
                          color: Color(0xFFC6F3D7),
                          size: 15,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'The details, handled.',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class OnboardingMessage extends StatelessWidget {
  const OnboardingMessage({
    super.key,
    required this.message,
    this.error = false,
  });
  final String message;
  final bool error;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = error ? cs.error : cs.primary;
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              error
                  ? Icons.info_outline_rounded
                  : Icons.check_circle_outline_rounded,
              color: color,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: color, height: 1.45),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
