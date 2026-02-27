import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/share_repository.dart';
import '../models/share_models.dart';

class ShareViewScreen extends ConsumerStatefulWidget {
  const ShareViewScreen({
    super.key,
    required this.shareId,
  });

  final String shareId;

  @override
  ConsumerState<ShareViewScreen> createState() => _ShareViewScreenState();
}

class _ShareViewScreenState extends ConsumerState<ShareViewScreen> {
  PublicShare? _share;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final share = await ref.read(shareRepositoryProvider).getPublicShare(widget.shareId);
      setState(() {
        _share = share;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Shared ReceiptNest AI View')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Failed to load share: $_error'))
              : _share == null
                  ? const Center(child: Text('This share link does not exist.'))
                  : _share!.type == PublicShareType.graph
                      ? _GraphShareCard(share: _share!.graph!)
                      : _ChatShareCard(share: _share!.chat!),
    );
  }
}

class _GraphShareCard extends StatelessWidget {
  const _GraphShareCard({required this.share});

  final GraphShare share;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(share.monthLabel, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text('Total spend: \$${share.totalSpend.toStringAsFixed(2)}'),
                if (share.includeName && (share.ownerName ?? '').isNotEmpty)
                  Text('Shared by: ${share.ownerName}'),
                if (share.includeEmail && (share.ownerEmail ?? '').isNotEmpty)
                  Text('Email: ${share.ownerEmail}'),
                const SizedBox(height: 12),
                SizedBox(
                  height: 220,
                  child: CustomPaint(
                    painter: _GraphPainter(points: share.dailyData),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ChatShareCard extends StatelessWidget {
  const _ChatShareCard({required this.share});

  final ChatShare share;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              share.title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        ),
        ...share.messages.map((message) {
          final userMessage = message.role == 'user';
          return Align(
            alignment: userMessage ? Alignment.centerRight : Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Card(
                color: userMessage ? Theme.of(context).colorScheme.primaryContainer : null,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(message.content),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _GraphPainter extends CustomPainter {
  _GraphPainter({required this.points});

  final List<GraphSharePoint> points;

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFFE2E8F0);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12)),
      background,
    );

    if (points.isEmpty) return;

    final maxY = points.map((p) => p.amount).fold<double>(0, (a, b) => a > b ? a : b);
    final safeMax = maxY <= 0 ? 1 : maxY;

    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final point = points[i];
      final x = (i / (points.length - 1).clamp(1, 9999)) * size.width;
      final y = size.height - ((point.amount / safeMax) * (size.height - 12)) - 6;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = const Color(0xFF0F766E)
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _GraphPainter oldDelegate) {
    return oldDelegate.points != points;
  }
}
