import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/utils/formatters.dart';
import '../../auth/data/auth_repository.dart';
import '../../receipts/data/receipt_repository.dart';
import '../../receipts/models/receipt.dart';
import '../../receipts/presentation/upload_receipt_sheet.dart';
import '../../share/data/share_repository.dart';
import '../../share/models/share_models.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  bool _loadingForwarding = false;
  String? _forwardingAddress;
  List<String> _fallbackAddresses = const [];
  String? _forwardingError;

  @override
  void initState() {
    super.initState();
    _loadForwardingAddress();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadForwardingAddress() async {
    setState(() {
      _loadingForwarding = true;
      _forwardingError = null;
    });

    try {
      final result = await ref
          .read(receiptRepositoryProvider)
          .generateForwardingAddress();
      setState(() {
        _forwardingAddress = result['emailAddress']?.toString();
        _fallbackAddresses =
            (result['fallbackAddresses'] as List<dynamic>? ?? const [])
                .map((e) => e.toString())
                .where((e) => e.isNotEmpty)
                .toList();
      });
    } catch (e) {
      setState(() {
        _forwardingError = 'Email forwarding is not configured yet.';
      });
    } finally {
      if (mounted) {
        setState(() => _loadingForwarding = false);
      }
    }
  }

  void _changeMonth(int delta) {
    final month = ref.read(selectedMonthProvider);
    final year = ref.read(selectedYearProvider);
    final current = DateTime(year, month, 1);
    final next = DateTime(current.year, current.month + delta, 1);
    ref.read(selectedMonthProvider.notifier).state = next.month;
    ref.read(selectedYearProvider.notifier).state = next.year;
  }

  Future<void> _shareGraph() async {
    final profile = ref.read(currentUserProfileProvider).valueOrNull;
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;

    final points = ref.read(dailySpendingDataProvider);
    final month = ref.read(selectedMonthProvider);
    final year = ref.read(selectedYearProvider);
    final monthLabel = ref.read(selectedMonthLabelProvider);
    final spend = ref.read(selectedMonthSpendProvider);

    if (points.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No data available for this month.')),
      );
      return;
    }

    try {
      final share = await ref
          .read(shareRepositoryProvider)
          .createGraphShare(
            userId: uid,
            month: month,
            year: year,
            monthLabel: monthLabel,
            totalSpend: spend,
            dailyData: points
                .map(
                  (point) => GraphSharePoint(
                    day: point.day,
                    amount: point.amount,
                    cumulative: point.cumulative,
                  ),
                )
                .toList(),
            includeName: true,
            includeEmail: true,
            ownerName: profile?.displayName,
            ownerEmail: profile?.email,
          );

      final link = 'https://receiptnest.web.app/share/${share.id}';
      await SharePlus.instance.share(ShareParams(text: link));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to share graph: $e')));
    }
  }

  void _openUpload() {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return UploadReceiptSheet(
          userId: uid,
          repository: ref.read(receiptRepositoryProvider),
          onUploaded: (_) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Receipt uploaded. Processing started.'),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final monthLabel = ref.watch(selectedMonthLabelProvider);
    final spend = ref.watch(selectedMonthSpendProvider);
    final monthChange = ref.watch(monthOverMonthChangeProvider);
    final dailyPoints = ref.watch(dailySpendingDataProvider);
    final month = ref.watch(selectedMonthProvider);
    final year = ref.watch(selectedYearProvider);
    final receiptsAsync = ref.watch(receiptsStreamProvider);
    final today = DateTime.now();
    final isCurrentMonth = month == today.month && year == today.year;
    final lastVisibleDay = isCurrentMonth
        ? math.min(today.day, math.max(1, dailyPoints.length))
        : math.max(1, dailyPoints.length);
    final trendColor = monthChange == null
        ? const Color(0xFF00C805)
        : (monthChange.isIncrease
              ? const Color(0xFFE53935)
              : const Color(0xFF00C805));

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: _openUpload,
        elevation: 2,
        child: const Icon(Icons.add_rounded),
      ),
      body: receiptsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Failed to load receipts: $err')),
        data: (receipts) {
          final filtered = receipts.where((receipt) {
            final query = _searchQuery.trim().toLowerCase();
            if (query.isEmpty) return true;

            final merchant =
                (receipt.merchant?.canonicalName ??
                        receipt.merchant?.rawName ??
                        '')
                    .toLowerCase();
            final fileName = receipt.file.originalName.toLowerCase();
            final date = receipt.date?.toLowerCase() ?? '';
            final amount = receipt.totalAmount?.toString() ?? '';

            return merchant.contains(query) ||
                fileName.contains(query) ||
                date.contains(query) ||
                amount.contains(query);
          }).toList();

          return RefreshIndicator(
            onRefresh: _loadForwardingAddress,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              children: [
                // ── Spending card ──
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              onPressed: () => _changeMonth(-1),
                              icon: const Icon(Icons.chevron_left_rounded),
                              style: IconButton.styleFrom(
                                backgroundColor: cs.primary.withValues(alpha: 0.06),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                monthLabel,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => _changeMonth(1),
                              icon: const Icon(Icons.chevron_right_rounded),
                              style: IconButton.styleFrom(
                                backgroundColor: cs.primary.withValues(alpha: 0.06),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          formatCurrency(spend),
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                              ),
                        ),
                        const SizedBox(height: 4),
                        _MonthChangeLabel(change: monthChange, color: trendColor),
                        const SizedBox(height: 16),
                        _RobinhoodMonthlyChart(
                          points: dailyPoints,
                          lineColor: trendColor,
                          visibleDay: lastVisibleDay,
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: _shareGraph,
                              icon: const Icon(Icons.share_outlined, size: 18),
                              label: const Text('Share'),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: () => context.push('/app/pricing'),
                              icon: const Icon(Icons.diamond_outlined, size: 18),
                              label: const Text('Pricing'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Email forwarding ──
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: cs.primary.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.email_outlined,
                                size: 18,
                                color: cs.primary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Email forwarding',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (_loadingForwarding)
                          const LinearProgressIndicator()
                        else if (_forwardingError != null)
                          Text(
                            _forwardingError!,
                            style: TextStyle(
                              color: cs.error,
                              fontSize: 13,
                            ),
                          )
                        else if (_forwardingAddress != null) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.04)
                                  : Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: SelectableText(
                              _forwardingAddress!,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 13,
                                color: cs.onSurface.withValues(alpha: 0.8),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              OutlinedButton.icon(
                                onPressed: () {
                                  Clipboard.setData(
                                    ClipboardData(text: _forwardingAddress!),
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Copied to clipboard')),
                                  );
                                },
                                icon: const Icon(Icons.copy_rounded, size: 16),
                                label: const Text('Copy'),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                onPressed: _loadForwardingAddress,
                                icon: const Icon(Icons.refresh_rounded, size: 16),
                                label: const Text('Refresh'),
                              ),
                            ],
                          ),
                          if (_fallbackAddresses.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(
                              'Fallback addresses',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: cs.onSurface.withValues(alpha: 0.5),
                                  ),
                            ),
                            const SizedBox(height: 4),
                            ..._fallbackAddresses.map(
                              (item) => Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: SelectableText(
                                  item,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontFamily: 'monospace',
                                    color: cs.onSurface.withValues(alpha: 0.6),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ] else
                          Text(
                            'No forwarding address yet.',
                            style: TextStyle(
                              color: cs.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),

                // ── Search ──
                TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _searchQuery = value),
                  decoration: InputDecoration(
                    hintText: 'Search receipts...',
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: cs.onSurface.withValues(alpha: 0.4),
                    ),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                            icon: const Icon(Icons.clear_rounded, size: 20),
                          ),
                  ),
                ),
                const SizedBox(height: 16),

                // ── Receipts header ──
                Row(
                  children: [
                    Text(
                      'Receipts',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${filtered.length}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: cs.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (filtered.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          Icon(
                            Icons.receipt_long_outlined,
                            size: 40,
                            color: cs.onSurface.withValues(alpha: 0.2),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No receipts found',
                            style: TextStyle(
                              color: cs.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ...filtered
                      .take(100)
                      .map((receipt) => _ReceiptTile(receipt: receipt)),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Month-over-month label ──
class _MonthChangeLabel extends StatelessWidget {
  const _MonthChangeLabel({required this.change, required this.color});

  final dynamic change;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (change == null) {
      return Text(
        'No previous month data',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
            ),
      );
    }

    return Row(
      children: [
        Icon(
          change.isIncrease ? Icons.trending_up_rounded : Icons.trending_down_rounded,
          size: 18,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(
          '${change.isIncrease ? 'Up' : 'Down'} ${change.percent}% vs last month',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }
}

// ── Receipt tile ──
class _ReceiptTile extends ConsumerWidget {
  const _ReceiptTile({required this.receipt});

  final Receipt receipt;

  Color _badgeColor(BuildContext context) {
    switch (receipt.status) {
      case ReceiptStatuses.uploaded:
        return Colors.blue;
      case ReceiptStatuses.processing:
        return Colors.amber.shade700;
      case ReceiptStatuses.extracted:
        return Colors.teal;
      case ReceiptStatuses.needsReview:
        return Colors.orange;
      case ReceiptStatuses.finalStatus:
        return const Color(0xFF00C805);
      default:
        return Theme.of(context).colorScheme.secondary;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final merchant =
        receipt.merchant?.canonicalName ??
        receipt.merchant?.rawName ??
        receipt.extraction?.supplierName?.value?.toString() ??
        'Unknown merchant';

    final repository = ref.read(receiptRepositoryProvider);
    final badge = _badgeColor(context);

    return Card(
      child: InkWell(
        onTap: () => context.push('/app/receipt/${receipt.id}'),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Thumbnail
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: cs.primary.withValues(alpha: 0.06),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: receipt.isPdf
                      ? Icon(
                          Icons.picture_as_pdf_outlined,
                          color: cs.primary.withValues(alpha: 0.5),
                        )
                      : FutureBuilder<String>(
                          future: repository.getReceiptFileUrl(
                            receipt.file.storagePath,
                          ),
                          builder: (context, snapshot) {
                            final url = snapshot.data;
                            if (url == null) {
                              return Icon(
                                Icons.image_outlined,
                                color: cs.primary.withValues(alpha: 0.5),
                              );
                            }

                            return CachedNetworkImage(
                              imageUrl: url,
                              fit: BoxFit.cover,
                              errorWidget: (_, error, stackTrace) =>
                                  const Icon(Icons.broken_image_outlined),
                            );
                          },
                        ),
                ),
              ),
              const SizedBox(width: 14),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      merchant,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${formatDate(receipt.effectiveDate, pattern: 'MMM d')} \u2022 ${formatCurrency(receipt.totalAmount)}',
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: badge.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        receipt.status,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: badge,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: cs.onSurface.withValues(alpha: 0.25),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Chart ──
class _RobinhoodMonthlyChart extends StatelessWidget {
  const _RobinhoodMonthlyChart({
    required this.points,
    required this.lineColor,
    required this.visibleDay,
  });

  final List<DailySpendingPoint> points;
  final Color lineColor;
  final int visibleDay;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final safePoints = points.isEmpty
        ? const [DailySpendingPoint(day: 1, amount: 0, cumulative: 0)]
        : points;
    final clippedVisibleDay = math.min(
      math.max(1, visibleDay),
      safePoints.length,
    );
    final visiblePoints = safePoints
        .take(clippedVisibleDay)
        .toList(growable: false);

    var peak = visiblePoints.first;
    for (final point in visiblePoints) {
      if (point.amount > peak.amount) {
        peak = point;
      }
    }

    final totalSoFar = visiblePoints.fold<double>(
      0,
      (runningTotal, point) => runningTotal + point.amount,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 182,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                lineColor.withValues(alpha: 0.08),
                cs.surface.withValues(alpha: 0.95),
              ],
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: CustomPaint(
              painter: _RobinhoodChartPainter(
                points: visiblePoints,
                lineColor: lineColor,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Day 1',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.4),
                  ),
            ),
            Text(
              'Day ${visiblePoints.last.day}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface.withValues(alpha: 0.7),
                  ),
            ),
            Text(
              'Day ${safePoints.length}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.4),
                  ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _ChartPill(
              label: 'Spent',
              value: formatCurrency(totalSoFar),
              color: lineColor,
            ),
            const SizedBox(width: 8),
            _ChartPill(
              label: 'Peak',
              value: 'Day ${peak.day}: ${formatCurrency(peak.amount)}',
              color: cs.secondary,
            ),
          ],
        ),
      ],
    );
  }
}

class _ChartPill extends StatelessWidget {
  const _ChartPill({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
          ),
          children: [
            TextSpan(
              text: '$label  ',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: color,
                fontSize: 11,
              ),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

class _RobinhoodChartPainter extends CustomPainter {
  const _RobinhoodChartPainter({required this.points, required this.lineColor});

  final List<DailySpendingPoint> points;
  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    const horizontalPadding = 12.0;
    const topPadding = 12.0;
    const bottomPadding = 14.0;
    const gridLines = 4;

    final chartRect = Rect.fromLTWH(
      horizontalPadding,
      topPadding,
      size.width - (horizontalPadding * 2),
      size.height - topPadding - bottomPadding,
    );

    final gridPaint = Paint()
      ..color = lineColor.withValues(alpha: 0.08)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    for (var i = 0; i <= gridLines; i++) {
      final y = chartRect.top + (chartRect.height / gridLines) * i;
      canvas.drawLine(
        Offset(chartRect.left, y),
        Offset(chartRect.right, y),
        gridPaint,
      );
    }

    if (points.isEmpty) {
      return;
    }

    final maxAmount = math.max(
      points.fold<double>(
        0,
        (maxValue, point) => math.max(maxValue, point.amount),
      ),
      1.0,
    );

    Offset pointAt(int index) {
      final xFactor = points.length == 1 ? 1.0 : index / (points.length - 1);
      final x = chartRect.left + (chartRect.width * xFactor);
      final yFactor = points[index].amount / maxAmount;
      final y = chartRect.bottom - (chartRect.height * yFactor);
      return Offset(x, y);
    }

    final seriesPoints = List<Offset>.generate(points.length, pointAt);
    final linePath = Path();
    final firstPoint = seriesPoints.first;
    linePath.moveTo(firstPoint.dx, firstPoint.dy);
    if (seriesPoints.length == 1) {
      linePath.lineTo(firstPoint.dx, firstPoint.dy);
    } else {
      for (var i = 0; i < seriesPoints.length - 1; i++) {
        final current = seriesPoints[i];
        final next = seriesPoints[i + 1];
        final midX = (current.dx + next.dx) / 2;
        linePath.cubicTo(midX, current.dy, midX, next.dy, next.dx, next.dy);
      }
    }

    final lastPoint = seriesPoints.last;
    final fillPath = Path.from(linePath)
      ..lineTo(lastPoint.dx, chartRect.bottom)
      ..lineTo(firstPoint.dx, chartRect.bottom)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          lineColor.withValues(alpha: 0.28),
          lineColor.withValues(alpha: 0.02),
        ],
      ).createShader(chartRect)
      ..style = PaintingStyle.fill;
    canvas.drawPath(fillPath, fillPaint);

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(linePath, linePaint);

    // Marker with glow
    final glowPaint = Paint()
      ..color = lineColor.withValues(alpha: 0.20)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(lastPoint, 6, glowPaint);

    final markerPaint = Paint()..color = lineColor;
    final markerOutline = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawCircle(lastPoint, 4.5, markerPaint);
    canvas.drawCircle(lastPoint, 7, markerOutline);
  }

  @override
  bool shouldRepaint(covariant _RobinhoodChartPainter oldDelegate) {
    if (oldDelegate.lineColor != lineColor) {
      return true;
    }
    if (oldDelegate.points.length != points.length) {
      return true;
    }
    if (points.isEmpty) {
      return false;
    }
    return oldDelegate.points.last.amount != points.last.amount;
  }
}
