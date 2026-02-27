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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openUpload,
        icon: const Icon(Icons.add),
        label: const Text('Add receipt'),
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
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              onPressed: () => _changeMonth(-1),
                              icon: const Icon(Icons.chevron_left),
                            ),
                            Expanded(
                              child: Text(
                                monthLabel,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            IconButton(
                              onPressed: () => _changeMonth(1),
                              icon: const Icon(Icons.chevron_right),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          formatCurrency(spend),
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          monthChange == null
                              ? 'No previous month data'
                              : '${monthChange.isIncrease ? 'Up' : 'Down'} ${monthChange.percent}% vs previous month',
                        ),
                        const SizedBox(height: 12),
                        _RobinhoodMonthlyChart(
                          points: dailyPoints,
                          lineColor: trendColor,
                          visibleDay: lastVisibleDay,
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: _shareGraph,
                              icon: const Icon(Icons.share_outlined),
                              label: const Text('Share graph'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => context.push('/app/pricing'),
                              icon: const Icon(
                                Icons.currency_exchange_outlined,
                              ),
                              label: const Text('Pricing'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Email forwarding',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        if (_loadingForwarding)
                          const LinearProgressIndicator()
                        else if (_forwardingError != null)
                          Text(
                            _forwardingError!,
                            style: const TextStyle(color: Colors.redAccent),
                          )
                        else if (_forwardingAddress != null) ...[
                          SelectableText(_forwardingAddress!),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              OutlinedButton(
                                onPressed: () => Clipboard.setData(
                                  ClipboardData(text: _forwardingAddress!),
                                ),
                                child: const Text('Copy primary'),
                              ),
                              OutlinedButton(
                                onPressed: _loadForwardingAddress,
                                child: const Text('Refresh'),
                              ),
                            ],
                          ),
                          if (_fallbackAddresses.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            const Text('Fallback addresses'),
                            ..._fallbackAddresses.map(
                              (item) => SelectableText(item),
                            ),
                          ],
                        ] else
                          const Text('No forwarding address yet.'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _searchQuery = value),
                  decoration: InputDecoration(
                    hintText:
                        'Search receipts by merchant, amount, date, file name',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                            icon: const Icon(Icons.clear),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Receipts (${filtered.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (filtered.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('No receipts found.'),
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

class _ReceiptTile extends ConsumerWidget {
  const _ReceiptTile({required this.receipt});

  final Receipt receipt;

  Color _badgeColor(BuildContext context) {
    switch (receipt.status) {
      case ReceiptStatuses.uploaded:
        return Colors.blue;
      case ReceiptStatuses.processing:
        return Colors.amber;
      case ReceiptStatuses.extracted:
        return Colors.teal;
      case ReceiptStatuses.needsReview:
        return Colors.orange;
      case ReceiptStatuses.finalStatus:
        return Colors.green;
      default:
        return Theme.of(context).colorScheme.secondary;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final merchant =
        receipt.merchant?.canonicalName ??
        receipt.merchant?.rawName ??
        receipt.extraction?.supplierName?.value?.toString() ??
        'Unknown merchant';

    final repository = ref.read(receiptRepositoryProvider);

    return Card(
      child: ListTile(
        onTap: () => context.push('/app/receipt/${receipt.id}'),
        leading: SizedBox(
          width: 48,
          height: 48,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: receipt.isPdf
                ? const ColoredBox(
                    color: Color(0xFFEEF2FF),
                    child: Icon(Icons.picture_as_pdf_outlined),
                  )
                : FutureBuilder<String>(
                    future: repository.getReceiptFileUrl(
                      receipt.file.storagePath,
                    ),
                    builder: (context, snapshot) {
                      final url = snapshot.data;
                      if (url == null) {
                        return const ColoredBox(
                          color: Color(0xFFEEF2FF),
                          child: Icon(Icons.image_outlined),
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
        title: Text(merchant, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${formatDate(receipt.effectiveDate, pattern: 'MMM d')} • ${formatCurrency(receipt.totalAmount)}',
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: _badgeColor(context).withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                receipt.status,
                style: TextStyle(fontSize: 11, color: _badgeColor(context)),
              ),
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

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
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                lineColor.withValues(alpha: 0.10),
                Theme.of(context).colorScheme.surface.withValues(alpha: 0.95),
              ],
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: CustomPaint(
              painter: _RobinhoodChartPainter(
                points: visiblePoints,
                lineColor: lineColor,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Day 1', style: Theme.of(context).textTheme.bodySmall),
            Text(
              'Day ${visiblePoints.last.day}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            Text(
              'Day ${safePoints.length}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ChartPill(
              label: 'Spent so far',
              value: formatCurrency(totalSoFar),
              color: lineColor,
            ),
            _ChartPill(
              label: 'Peak day',
              value: 'Day ${peak.day}: ${formatCurrency(peak.amount)}',
              color: Theme.of(context).colorScheme.secondary,
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(999),
      ),
      child: RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
          ),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(text: value),
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
    const horizontalPadding = 10.0;
    const topPadding = 10.0;
    const bottomPadding = 14.0;
    const gridLines = 4;

    final chartRect = Rect.fromLTWH(
      horizontalPadding,
      topPadding,
      size.width - (horizontalPadding * 2),
      size.height - topPadding - bottomPadding,
    );

    final gridPaint = Paint()
      ..color = lineColor.withValues(alpha: 0.12)
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
          lineColor.withValues(alpha: 0.34),
          lineColor.withValues(alpha: 0.03),
        ],
      ).createShader(chartRect)
      ..style = PaintingStyle.fill;
    canvas.drawPath(fillPath, fillPaint);

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(linePath, linePaint);

    final markerPaint = Paint()..color = lineColor;
    final markerOutline = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;
    canvas.drawCircle(lastPoint, 4.8, markerPaint);
    canvas.drawCircle(lastPoint, 8.2, markerOutline);
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
