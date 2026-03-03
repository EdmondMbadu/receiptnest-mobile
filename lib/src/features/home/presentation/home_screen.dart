import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/utils/formatters.dart';
import '../../auth/data/auth_repository.dart';
import '../../receipts/data/receipt_repository.dart';
import '../../receipts/models/receipt.dart';
import '../../receipts/presentation/upload_receipt_sheet.dart';
import '../../share/data/share_repository.dart';
import '../../share/models/share_models.dart';

enum _GraphViewMode { month, histogram }

enum _TimeRange { oneDay, oneWeek, oneMonth, threeMonths, oneYear, all }

enum _HistogramRange { thisYear, fiveYears, all }

String _timeRangeLabel(_TimeRange range) {
  switch (range) {
    case _TimeRange.oneDay:
      return '1D';
    case _TimeRange.oneWeek:
      return '1W';
    case _TimeRange.oneMonth:
      return '1M';
    case _TimeRange.threeMonths:
      return '3M';
    case _TimeRange.oneYear:
      return '1Y';
    case _TimeRange.all:
      return 'All';
  }
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  static const _receiptBatchSize = 20;

  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  String _searchQuery = '';
  int _visibleReceiptCount = _receiptBatchSize;
  int _latestFilteredCount = 0;
  _GraphViewMode _graphViewMode = _GraphViewMode.month;
  _TimeRange _timeRange = _TimeRange.oneMonth;
  _HistogramRange _histogramRange = _HistogramRange.thisYear;

  bool _loadingForwarding = false;
  String? _forwardingAddress;
  String? _forwardingError;

  @override
  void initState() {
    super.initState();
    _loadForwardingAddress();
    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter > 360) return;
    if (_visibleReceiptCount >= _latestFilteredCount) return;

    setState(() {
      _visibleReceiptCount = math.min(
        _visibleReceiptCount + _receiptBatchSize,
        _latestFilteredCount,
      );
    });
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

  Future<void> _refreshHome() async {
    await _loadForwardingAddress();
    if (!mounted) return;
    setState(() => _visibleReceiptCount = _receiptBatchSize);
  }

  void _changeMonth(int delta) {
    final month = ref.read(selectedMonthProvider);
    final year = ref.read(selectedYearProvider);
    final current = DateTime(year, month, 1);
    final next = DateTime(current.year, current.month + delta, 1);
    ref.read(selectedMonthProvider.notifier).state = next.month;
    ref.read(selectedYearProvider.notifier).state = next.year;
  }

  void _setGraphViewMode(_GraphViewMode mode) {
    if (_graphViewMode == mode) return;
    setState(() => _graphViewMode = mode);
  }

  void _setTimeRange(_TimeRange range) {
    if (_timeRange == range) return;
    setState(() => _timeRange = range);
  }

  void _setHistogramRange(_HistogramRange range) {
    if (_histogramRange == range) return;
    setState(() => _histogramRange = range);
  }

  /// Builds daily spending points for the selected time range.
  List<DailySpendingPoint> _buildTimeRangeData(List<Receipt> receipts) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    late DateTime startDate;
    switch (_timeRange) {
      case _TimeRange.oneDay:
        startDate = today;
        break;
      case _TimeRange.oneWeek:
        startDate = today.subtract(const Duration(days: 6));
        break;
      case _TimeRange.oneMonth:
        startDate = DateTime(today.year, today.month - 1, today.day);
        break;
      case _TimeRange.threeMonths:
        startDate = DateTime(today.year, today.month - 3, today.day);
        break;
      case _TimeRange.oneYear:
        startDate = DateTime(today.year - 1, today.month, today.day);
        break;
      case _TimeRange.all:
        DateTime? earliest;
        for (final r in receipts) {
          final d = r.effectiveDate;
          if (d != null && (earliest == null || d.isBefore(earliest))) {
            earliest = d;
          }
        }
        startDate = earliest ?? today;
        break;
    }

    final dayAmounts = <int, double>{};
    final totalDays = today.difference(startDate).inDays + 1;

    for (final receipt in receipts) {
      final amount = receipt.effectiveTotalAmount;
      final date = receipt.effectiveDate;
      if (amount == null || date == null) continue;
      final receiptDay = DateTime(date.year, date.month, date.day);
      if (receiptDay.isBefore(startDate) || receiptDay.isAfter(today)) continue;
      final dayIndex = receiptDay.difference(startDate).inDays;
      dayAmounts[dayIndex] = (dayAmounts[dayIndex] ?? 0) + amount;
    }

    var cumulative = 0.0;
    return List.generate(math.max(1, totalDays), (index) {
      final amount = dayAmounts[index] ?? 0;
      cumulative += amount;
      return DailySpendingPoint(
        day: index + 1,
        amount: amount,
        cumulative: cumulative,
      );
    });
  }

  double _timeRangeSpend(List<DailySpendingPoint> points) {
    return points.fold<double>(0, (sum, p) => sum + p.amount);
  }

  String _timeRangeSubtitle() {
    switch (_timeRange) {
      case _TimeRange.oneDay:
        return 'Today';
      case _TimeRange.oneWeek:
        return 'Past 7 days';
      case _TimeRange.oneMonth:
        return 'Past month';
      case _TimeRange.threeMonths:
        return 'Past 3 months';
      case _TimeRange.oneYear:
        return 'Past year';
      case _TimeRange.all:
        return 'All time';
    }
  }

  static const _shortMonthLabels = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static const _longMonthLabels = <String>[
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  String _histogramRangeTitle(_HistogramRange range) {
    switch (range) {
      case _HistogramRange.thisYear:
        return 'This year';
      case _HistogramRange.fiveYears:
        return 'Last 5 years';
      case _HistogramRange.all:
        return 'All time';
    }
  }

  String _monthKey(int year, int month) {
    return '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';
  }

  List<_HistogramMonthPoint> _buildHistogramMonthlyData(
    List<Receipt> receipts,
  ) {
    final now = DateTime.now();
    final endMonth = DateTime(now.year, now.month, 1);
    final monthlyTotals = <String, double>{};
    DateTime? earliestMonth;

    for (final receipt in receipts) {
      final amount = receipt.effectiveTotalAmount;
      final date = receipt.effectiveDate;
      if (amount == null || date == null) continue;

      final monthDate = DateTime(date.year, date.month, 1);
      if (earliestMonth == null || monthDate.isBefore(earliestMonth)) {
        earliestMonth = monthDate;
      }

      final key = _monthKey(monthDate.year, monthDate.month);
      monthlyTotals[key] = (monthlyTotals[key] ?? 0) + amount;
    }

    var startMonth = DateTime(now.year, 1, 1);
    if (_histogramRange == _HistogramRange.fiveYears) {
      startMonth = DateTime(endMonth.year, endMonth.month - 59, 1);
    } else if (_histogramRange == _HistogramRange.all) {
      startMonth = earliestMonth ?? endMonth;
    }

    if (startMonth.isAfter(endMonth)) {
      startMonth = endMonth;
    }

    final data = <_HistogramMonthPoint>[];
    var cursor = DateTime(startMonth.year, startMonth.month, 1);

    while (!cursor.isAfter(endMonth)) {
      final key = _monthKey(cursor.year, cursor.month);
      final short = _shortMonthLabels[cursor.month - 1];
      final long = _longMonthLabels[cursor.month - 1];
      final shortYear = (cursor.year % 100).toString().padLeft(2, '0');
      final label = _histogramRange == _HistogramRange.thisYear
          ? short
          : '$short $shortYear';
      final fullLabel = '$long ${cursor.year}';

      data.add(
        _HistogramMonthPoint(
          monthKey: key,
          month: cursor.month,
          year: cursor.year,
          label: label,
          fullLabel: fullLabel,
          amount: monthlyTotals[key] ?? 0,
        ),
      );

      cursor = DateTime(cursor.year, cursor.month + 1, 1);
    }

    return data;
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
    final totalDaysInMonth = DateTime(year, month + 1, 0).day;
    final lastVisibleDay = isCurrentMonth
        ? math.min(today.day, totalDaysInMonth)
        : totalDaysInMonth;
    final trendColor = monthChange == null
        ? const Color(0xFF00C805)
        : (monthChange.isIncrease
              ? const Color(0xFFE53935)
              : const Color(0xFF00C805));
    const histogramColor = Color(0xFF00C805);

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
          final histogramMonthlyData = _buildHistogramMonthlyData(receipts);
          final histogramTotalSpend = histogramMonthlyData.fold<double>(
            0,
            (sum, point) => sum + point.amount,
          );
          final timeRangePoints = _buildTimeRangeData(receipts);
          final timeRangeTotal = _timeRangeSpend(timeRangePoints);
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
            final amount = receipt.effectiveTotalAmount?.toString() ?? '';

            return merchant.contains(query) ||
                fileName.contains(query) ||
                date.contains(query) ||
                amount.contains(query);
          }).toList();
          _latestFilteredCount = filtered.length;
          final visibleReceipts = filtered
              .take(math.min(_visibleReceiptCount, filtered.length))
              .toList(growable: false);
          final hasMoreVisible = visibleReceipts.length < filtered.length;

          return RefreshIndicator(
            onRefresh: _refreshHome,
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              children: [
                // ── Spending card ──
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isDark
                          ? [
                              const Color(0xFF1A1A2E),
                              const Color(0xFF16161F),
                            ]
                          : [
                              Colors.white,
                              const Color(0xFFF8FAFE),
                            ],
                    ),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : Colors.grey.shade200,
                    ),
                    boxShadow: isDark
                        ? null
                        : [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 20,
                              offset: const Offset(0, 4),
                            ),
                          ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Custom view mode toggle ──
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.06)
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              for (final mode in _GraphViewMode.values)
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => _setGraphViewMode(mode),
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 200),
                                      curve: Curves.easeOut,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _graphViewMode == mode
                                            ? (isDark
                                                ? Colors.white.withValues(alpha: 0.12)
                                                : Colors.white)
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(11),
                                        boxShadow: _graphViewMode == mode && !isDark
                                            ? [
                                                BoxShadow(
                                                  color: Colors.black.withValues(alpha: 0.06),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ]
                                            : null,
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            mode == _GraphViewMode.month
                                                ? Icons.show_chart_rounded
                                                : Icons.bar_chart_rounded,
                                            size: 16,
                                            color: _graphViewMode == mode
                                                ? cs.primary
                                                : cs.onSurface.withValues(alpha: 0.4),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            mode == _GraphViewMode.month
                                                ? 'Spending'
                                                : 'Histogram',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: _graphViewMode == mode
                                                  ? FontWeight.w700
                                                  : FontWeight.w500,
                                              color: _graphViewMode == mode
                                                  ? cs.onSurface
                                                  : cs.onSurface.withValues(alpha: 0.45),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // ── Month view ──
                        if (_graphViewMode == _GraphViewMode.month) ...[
                          // Time range pills
                          Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.04)
                                  : Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: _TimeRange.values.map((range) {
                                final isSelected = range == _timeRange;
                                return Expanded(
                                  child: GestureDetector(
                                    onTap: () => _setTimeRange(range),
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 200,
                                      ),
                                      curve: Curves.easeOut,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? trendColor
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Center(
                                        child: Text(
                                          _timeRangeLabel(range),
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: isSelected
                                                ? Colors.white
                                                : cs.onSurface.withValues(
                                                    alpha: 0.4,
                                                  ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                          const SizedBox(height: 20),
                          // Month navigation (only for 1M)
                          if (_timeRange == _TimeRange.oneMonth) ...[
                            Row(
                              children: [
                                _NavArrowButton(
                                  icon: Icons.chevron_left_rounded,
                                  onTap: () => _changeMonth(-1),
                                  isDark: isDark,
                                ),
                                Expanded(
                                  child: Text(
                                    monthLabel,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: cs.onSurface,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                ),
                                _NavArrowButton(
                                  icon: Icons.chevron_right_rounded,
                                  onTap: () => _changeMonth(1),
                                  isDark: isDark,
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                          ],
                          // Subtitle for non-1M ranges
                          if (_timeRange != _TimeRange.oneMonth) ...[
                            Text(
                              _timeRangeSubtitle(),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: cs.onSurface.withValues(alpha: 0.6),
                                letterSpacing: -0.1,
                              ),
                            ),
                            const SizedBox(height: 4),
                          ],
                          // Amount
                          Text(
                            _timeRange == _TimeRange.oneMonth
                                ? formatCurrency(spend)
                                : formatCurrency(timeRangeTotal),
                            style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1.5,
                              height: 1.1,
                              color: cs.onSurface,
                            ),
                          ),
                          const SizedBox(height: 6),
                          if (_timeRange == _TimeRange.oneMonth)
                            _MonthChangeLabel(
                              change: monthChange,
                              color: trendColor,
                            )
                          else
                            Text(
                              _timeRangeSubtitle(),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: cs.onSurface.withValues(alpha: 0.45),
                              ),
                            ),
                          const SizedBox(height: 20),
                          // Chart
                          if (_timeRange == _TimeRange.oneMonth)
                            _RobinhoodMonthlyChart(
                              points: dailyPoints,
                              lineColor: trendColor,
                              visibleDay: lastVisibleDay,
                              totalDays: totalDaysInMonth,
                              isCurrentMonth: isCurrentMonth,
                            )
                          else
                            _RobinhoodTimeRangeChart(
                              points: timeRangePoints,
                              lineColor: trendColor,
                            ),
                        ],

                        // ── Histogram view ──
                        if (_graphViewMode == _GraphViewMode.histogram) ...[
                          // Custom histogram range toggle
                          Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.04)
                                  : Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                for (final range in _HistogramRange.values)
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () => _setHistogramRange(range),
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 200),
                                        curve: Curves.easeOut,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _histogramRange == range
                                              ? histogramColor
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Center(
                                          child: Text(
                                            range == _HistogramRange.thisYear
                                                ? 'This Year'
                                                : range == _HistogramRange.fiveYears
                                                    ? '5 Years'
                                                    : 'All',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: _histogramRange == range
                                                  ? Colors.white
                                                  : cs.onSurface.withValues(alpha: 0.4),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            _histogramRangeTitle(_histogramRange),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: cs.onSurface.withValues(alpha: 0.6),
                              letterSpacing: -0.1,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            formatCurrency(histogramTotalSpend),
                            style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1.5,
                              height: 1.1,
                              color: cs.onSurface,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Monthly spending trend',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: cs.onSurface.withValues(alpha: 0.45),
                            ),
                          ),
                          const SizedBox(height: 20),
                          _HistogramSpendingChart(
                            points: histogramMonthlyData,
                            lineColor: histogramColor,
                          ),
                        ],

                        const SizedBox(height: 16),
                        // ── Action buttons ──
                        Row(
                          children: [
                            if (_graphViewMode == _GraphViewMode.month) ...[
                              Expanded(
                                child: _ActionChip(
                                  icon: Icons.ios_share_rounded,
                                  label: 'Share',
                                  onTap: _shareGraph,
                                  color: cs.primary,
                                  isDark: isDark,
                                ),
                              ),
                              const SizedBox(width: 10),
                            ],
                            Expanded(
                              child: _ActionChip(
                                icon: Icons.diamond_outlined,
                                label: 'Pricing',
                                onTap: () => context.push('/app/pricing'),
                                color: cs.primary,
                                isDark: isDark,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // ── Email forwarding ──
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isDark
                          ? [
                              const Color(0xFF1A1A2E),
                              const Color(0xFF16161F),
                            ]
                          : [
                              Colors.white,
                              const Color(0xFFF8FAFE),
                            ],
                    ),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : Colors.grey.shade200,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    cs.primary.withValues(alpha: 0.15),
                                    cs.primary.withValues(alpha: 0.05),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.email_outlined,
                                size: 18,
                                color: cs.primary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Email Forwarding',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: cs.onSurface,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Forward receipts to auto-track',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: cs.onSurface.withValues(alpha: 0.45),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        if (_loadingForwarding)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              minHeight: 3,
                              backgroundColor: cs.primary.withValues(alpha: 0.08),
                            ),
                          )
                        else if (_forwardingError != null)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: cs.error.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _forwardingError!,
                              style: TextStyle(
                                color: cs.error,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          )
                        else if (_forwardingAddress != null) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.04)
                                  : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: SelectableText(
                              _forwardingAddress!,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                                color: cs.onSurface.withValues(alpha: 0.75),
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _ActionChip(
                                  icon: Icons.copy_rounded,
                                  label: 'Copy',
                                  onTap: () {
                                    Clipboard.setData(
                                      ClipboardData(text: _forwardingAddress!),
                                    );
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Copied to clipboard'),
                                      ),
                                    );
                                  },
                                  color: cs.primary,
                                  isDark: isDark,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _ActionChip(
                                  icon: Icons.refresh_rounded,
                                  label: 'Refresh',
                                  onTap: _loadForwardingAddress,
                                  color: cs.primary,
                                  isDark: isDark,
                                ),
                              ),
                            ],
                          ),
                        ] else
                          Text(
                            'No forwarding address yet.',
                            style: TextStyle(
                              color: cs.onSurface.withValues(alpha: 0.45),
                              fontSize: 13,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // ── Search ──
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.white,
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : Colors.grey.shade200,
                    ),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() {
                      _searchQuery = value;
                      _visibleReceiptCount = _receiptBatchSize;
                    }),
                    decoration: InputDecoration(
                      hintText: 'Search receipts...',
                      hintStyle: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.3),
                        fontWeight: FontWeight.w400,
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: cs.onSurface.withValues(alpha: 0.3),
                      ),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchQuery = '';
                                  _visibleReceiptCount = _receiptBatchSize;
                                });
                              },
                              icon: const Icon(Icons.clear_rounded, size: 18),
                            ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // ── Receipts header ──
                Row(
                  children: [
                    Text(
                      'Receipts',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(20),
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
                const SizedBox(height: 12),
                if (filtered.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.03)
                          : Colors.grey.shade50,
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: cs.onSurface.withValues(alpha: 0.05),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.receipt_long_outlined,
                            size: 32,
                            color: cs.onSurface.withValues(alpha: 0.2),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No receipts found',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface.withValues(alpha: 0.4),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Upload a receipt to get started',
                          style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurface.withValues(alpha: 0.3),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ...visibleReceipts.map(
                    (receipt) => _ReceiptTile(receipt: receipt),
                  ),
                if (hasMoreVisible)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Navigation arrow button ──
class _NavArrowButton extends StatelessWidget {
  const _NavArrowButton({
    required this.icon,
    required this.onTap,
    required this.isDark,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 20),
      ),
    );
  }
}

// ── Reusable action chip button ──
class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.color,
    required this.isDark,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.04)
                : Colors.grey.shade200,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
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
        style: TextStyle(
          fontSize: 13,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            change.isIncrease
                ? Icons.trending_up_rounded
                : Icons.trending_down_rounded,
            size: 15,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            '${change.percent}% vs last month',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Receipt tile ──
class _ReceiptTile extends ConsumerWidget {
  const _ReceiptTile({required this.receipt});

  final Receipt receipt;

  Color _statusColor(BuildContext context) {
    switch (receipt.status) {
      case ReceiptStatuses.uploaded:
        return const Color(0xFF3B82F6);
      case ReceiptStatuses.processing:
        return const Color(0xFFF59E0B);
      case ReceiptStatuses.extracted:
        return const Color(0xFF14B8A6);
      case ReceiptStatuses.needsReview:
        return const Color(0xFFF97316);
      case ReceiptStatuses.finalStatus:
        return const Color(0xFF22C55E);
      default:
        return Theme.of(context).colorScheme.secondary;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final merchant =
        receipt.merchant?.canonicalName ??
        receipt.merchant?.rawName ??
        receipt.extraction?.supplierName?.value?.toString() ??
        'Unknown merchant';

    final urlAsync = ref.watch(
      receiptFileUrlProvider(receipt.file.storagePath),
    );
    final statusColor = _statusColor(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        onTap: () => context.push('/app/receipt/${receipt.id}'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: isDark
                ? Colors.white.withValues(alpha: 0.03)
                : Colors.white,
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : const Color(0xFFEEF0F4),
            ),
          ),
          child: Row(
            children: [
              // Thumbnail
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : const Color(0xFFF4F6F8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: receipt.isPdf
                      ? Icon(
                          Icons.picture_as_pdf_outlined,
                          size: 20,
                          color: cs.primary.withValues(alpha: 0.45),
                        )
                      : urlAsync.when(
                          data: (url) => CachedNetworkImage(
                            imageUrl: url,
                            fit: BoxFit.cover,
                            errorWidget: (context, error, stackTrace) =>
                                Icon(
                                  Icons.broken_image_outlined,
                                  size: 20,
                                  color: cs.onSurface.withValues(alpha: 0.25),
                                ),
                          ),
                          loading: () => Icon(
                            Icons.image_outlined,
                            size: 20,
                            color: cs.primary.withValues(alpha: 0.35),
                          ),
                          error: (error, stackTrace) => Icon(
                            Icons.broken_image_outlined,
                            size: 20,
                            color: cs.onSurface.withValues(alpha: 0.25),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              // Left side: merchant + date
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      merchant,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14.5,
                        letterSpacing: -0.1,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      formatDate(receipt.effectiveDate, pattern: 'MMM d, yyyy'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: cs.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Right side: amount + status
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatCurrency(receipt.effectiveTotalAmount),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        receipt.status,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: cs.onSurface.withValues(alpha: 0.4),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Chart constants ──
const double _chartHorizontalPadding = 12.0;
const double _chartTopPadding = 12.0;
const double _chartBottomPadding = 14.0;

// ── Month chart (daily amounts, drops to 0) ──
class _RobinhoodMonthlyChart extends StatefulWidget {
  const _RobinhoodMonthlyChart({
    required this.points,
    required this.lineColor,
    required this.visibleDay,
    required this.totalDays,
    required this.isCurrentMonth,
  });

  final List<DailySpendingPoint> points;
  final Color lineColor;
  final int visibleDay;
  final int totalDays;
  final bool isCurrentMonth;

  @override
  State<_RobinhoodMonthlyChart> createState() => _RobinhoodMonthlyChartState();
}

class _RobinhoodMonthlyChartState extends State<_RobinhoodMonthlyChart> {
  int? _selectedIndex;

  @override
  void didUpdateWidget(covariant _RobinhoodMonthlyChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visibleDay != widget.visibleDay ||
        oldWidget.totalDays != widget.totalDays ||
        oldWidget.points.length != widget.points.length) {
      _selectedIndex = null;
    }
  }

  /// For the current month, show all days up to today so the graph
  /// looks like a timeline. For past months, condense to only days
  /// with spending so the graph is focused (Robinhood-style).
  List<DailySpendingPoint> _normalizedPoints() {
    final totalDays = math.max(1, widget.totalDays);
    final amountByDay = <int, double>{};
    for (final point in widget.points) {
      if (point.day >= 1 && point.day <= totalDays) {
        amountByDay[point.day] = point.amount;
      }
    }

    if (widget.isCurrentMonth) {
      // Current month: show all days (timeline view)
      var cumulative = 0.0;
      return List.generate(totalDays, (index) {
        final day = index + 1;
        final amount = amountByDay[day] ?? 0;
        cumulative += amount;
        return DailySpendingPoint(
          day: day,
          amount: amount,
          cumulative: cumulative,
        );
      });
    } else {
      // Past months: only days with spending (condensed view)
      final active = <DailySpendingPoint>[];
      var cumulative = 0.0;
      for (var day = 1; day <= totalDays; day++) {
        final amount = amountByDay[day];
        if (amount != null && amount > 0) {
          cumulative += amount;
          active.add(DailySpendingPoint(
            day: day,
            amount: amount,
            cumulative: cumulative,
          ));
        }
      }
      if (active.isEmpty) {
        return [const DailySpendingPoint(day: 1, amount: 0, cumulative: 0)];
      }
      return active;
    }
  }

  int _indexFromDx(double dx, double width, int count) {
    if (count <= 1) return 0;
    final chartWidth = math.max(1.0, width - (_chartHorizontalPadding * 2));
    final normalized = ((dx - _chartHorizontalPadding) / chartWidth).clamp(
      0.0,
      1.0,
    );
    return (normalized * (count - 1)).round();
  }

  void _updateSelection(double dx, double width, int count) {
    final nextIndex = _indexFromDx(dx, width, count);
    if (nextIndex == _selectedIndex) return;
    setState(() => _selectedIndex = nextIndex);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final safePoints = _normalizedPoints();
    final clippedVisibleDay = math.min(
      math.max(1, widget.visibleDay),
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
    final selectedPoint = _selectedIndex == null
        ? null
        : visiblePoints[_selectedIndex!.clamp(0, visiblePoints.length - 1)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 120),
          child: selectedPoint == null
              ? Text(
                  widget.isCurrentMonth
                      ? 'Touch and slide to inspect daily spend'
                      : 'Touch to inspect a day',
                  key: const ValueKey('hint'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.55),
                  ),
                )
              : Text(
                  'Day ${selectedPoint.day}: ${formatCurrency(selectedPoint.amount)}',
                  key: ValueKey<int>(selectedPoint.day),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: widget.lineColor,
                  ),
                ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 220,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                widget.lineColor.withValues(alpha: 0.08),
                cs.surface.withValues(alpha: 0.95),
              ],
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                return MouseRegion(
                  onHover: (event) => _updateSelection(
                    event.localPosition.dx,
                    width,
                    visiblePoints.length,
                  ),
                  onExit: (_) => setState(() => _selectedIndex = null),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (details) => _updateSelection(
                      details.localPosition.dx,
                      width,
                      visiblePoints.length,
                    ),
                    onPanStart: (details) => _updateSelection(
                      details.localPosition.dx,
                      width,
                      visiblePoints.length,
                    ),
                    onPanUpdate: (details) => _updateSelection(
                      details.localPosition.dx,
                      width,
                      visiblePoints.length,
                    ),
                    onPanEnd: (_) => setState(() => _selectedIndex = null),
                    child: CustomPaint(
                      painter: _RobinhoodChartPainter(
                        points: visiblePoints,
                        lineColor: widget.lineColor,
                        selectedIndex: _selectedIndex,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _ChartPill(
              label: 'Spent',
              value: formatCurrency(totalSoFar),
              color: widget.lineColor,
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

// ── Robinhood time-range chart (condensed – only days with spending) ──
class _RobinhoodTimeRangeChart extends StatefulWidget {
  const _RobinhoodTimeRangeChart({
    required this.points,
    required this.lineColor,
  });

  final List<DailySpendingPoint> points;
  final Color lineColor;

  @override
  State<_RobinhoodTimeRangeChart> createState() =>
      _RobinhoodTimeRangeChartState();
}

class _RobinhoodTimeRangeChartState extends State<_RobinhoodTimeRangeChart> {
  int? _selectedIndex;

  @override
  void didUpdateWidget(covariant _RobinhoodTimeRangeChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.points.length != widget.points.length) {
      _selectedIndex = null;
    }
  }

  /// Filter to only days that have spending, keeping the chart condensed.
  List<DailySpendingPoint> _condensedPoints() {
    final active = widget.points.where((p) => p.amount > 0).toList();
    if (active.isEmpty) {
      // Return at least one zero point so the chart doesn't crash
      return [const DailySpendingPoint(day: 1, amount: 0, cumulative: 0)];
    }
    return active;
  }

  int _indexFromDx(double dx, double width, int count) {
    if (count <= 1) return 0;
    final chartWidth = math.max(1.0, width - (_chartHorizontalPadding * 2));
    final normalized = ((dx - _chartHorizontalPadding) / chartWidth).clamp(
      0.0,
      1.0,
    );
    return (normalized * (count - 1)).round();
  }

  void _updateSelection(double dx, double width, int count) {
    final nextIndex = _indexFromDx(dx, width, count);
    if (nextIndex == _selectedIndex) return;
    setState(() => _selectedIndex = nextIndex);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final condensed = _condensedPoints();

    var peak = condensed.first;
    for (final point in condensed) {
      if (point.amount > peak.amount) peak = point;
    }

    final totalSpend = condensed.fold<double>(
      0,
      (sum, p) => sum + p.amount,
    );
    final selectedPoint = _selectedIndex == null
        ? null
        : condensed[_selectedIndex!.clamp(0, condensed.length - 1)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 120),
          child: selectedPoint == null
              ? Text(
                  'Touch and slide to inspect spending',
                  key: const ValueKey('hint'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.55),
                  ),
                )
              : Text(
                  'Day ${selectedPoint.day}: ${formatCurrency(selectedPoint.amount)}',
                  key: ValueKey<int>(selectedPoint.day),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: widget.lineColor,
                  ),
                ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 220,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                widget.lineColor.withValues(alpha: 0.08),
                cs.surface.withValues(alpha: 0.95),
              ],
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                return MouseRegion(
                  onHover: (event) => _updateSelection(
                    event.localPosition.dx,
                    width,
                    condensed.length,
                  ),
                  onExit: (_) => setState(() => _selectedIndex = null),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (details) => _updateSelection(
                      details.localPosition.dx,
                      width,
                      condensed.length,
                    ),
                    onPanStart: (details) => _updateSelection(
                      details.localPosition.dx,
                      width,
                      condensed.length,
                    ),
                    onPanUpdate: (details) => _updateSelection(
                      details.localPosition.dx,
                      width,
                      condensed.length,
                    ),
                    onPanEnd: (_) => setState(() => _selectedIndex = null),
                    child: CustomPaint(
                      painter: _RobinhoodChartPainter(
                        points: condensed,
                        lineColor: widget.lineColor,
                        selectedIndex: _selectedIndex,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _ChartPill(
              label: 'Spent',
              value: formatCurrency(totalSpend),
              color: widget.lineColor,
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

// ── Histogram data models ──
class _HistogramMonthPoint {
  const _HistogramMonthPoint({
    required this.monthKey,
    required this.month,
    required this.year,
    required this.label,
    required this.fullLabel,
    required this.amount,
  });

  final String monthKey;
  final int month;
  final int year;
  final String label;
  final String fullLabel;
  final double amount;
}

class _HistogramYAxisTick {
  const _HistogramYAxisTick({required this.fraction, required this.label});

  final double fraction;
  final String label;
}

// ── Histogram chart ──
class _HistogramSpendingChart extends StatefulWidget {
  const _HistogramSpendingChart({
    required this.points,
    required this.lineColor,
  });

  final List<_HistogramMonthPoint> points;
  final Color lineColor;

  @override
  State<_HistogramSpendingChart> createState() =>
      _HistogramSpendingChartState();
}

class _HistogramSpendingChartState extends State<_HistogramSpendingChart> {
  static final _axisSmallFormatter = NumberFormat.currency(
    symbol: r'$',
    decimalDigits: 0,
  );
  static final _axisCompactFormatter = NumberFormat.compactCurrency(
    symbol: r'$',
    decimalDigits: 1,
  );

  int? _selectedIndex;

  @override
  void didUpdateWidget(covariant _HistogramSpendingChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    final dataChanged =
        oldWidget.points.length != widget.points.length ||
        (oldWidget.points.isNotEmpty &&
            widget.points.isNotEmpty &&
            oldWidget.points.first.monthKey != widget.points.first.monthKey) ||
        (oldWidget.points.isNotEmpty &&
            widget.points.isNotEmpty &&
            oldWidget.points.last.monthKey != widget.points.last.monthKey);
    if (dataChanged) {
      _selectedIndex = null;
    }
  }

  int _indexFromDx(double dx, double width, int count) {
    if (count <= 1) return 0;
    final chartWidth = math.max(1.0, width - (_chartHorizontalPadding * 2));
    final normalized = ((dx - _chartHorizontalPadding) / chartWidth).clamp(
      0.0,
      1.0,
    );
    return (normalized * (count - 1)).round();
  }

  void _updateSelection(double dx, double width, int count) {
    final nextIndex = _indexFromDx(dx, width, count);
    if (nextIndex == _selectedIndex) return;
    setState(() => _selectedIndex = nextIndex);
  }

  List<_HistogramMonthPoint> _axisLabelPoints() {
    if (widget.points.isEmpty) return const [];
    final lastIndex = widget.points.length - 1;
    final indexes = {
      0,
      (lastIndex * 0.25).floor(),
      (lastIndex * 0.5).floor(),
      (lastIndex * 0.75).floor(),
      lastIndex,
    }.toList()..sort();

    return indexes.map((index) => widget.points[index]).toList(growable: false);
  }

  String _formatAxisAmount(double amount) {
    if (amount == 0) return r'$0';
    if (amount.abs() < 1000) return _axisSmallFormatter.format(amount);
    return _axisCompactFormatter.format(amount);
  }

  List<_HistogramYAxisTick> _yAxisTicks(double maxAmount) {
    if (maxAmount <= 0) {
      return const [_HistogramYAxisTick(fraction: 0, label: r'$0')];
    }
    return [1.0, 0.75, 0.5, 0.25, 0.0]
        .map(
          (fraction) => _HistogramYAxisTick(
            fraction: fraction,
            label: _formatAxisAmount(maxAmount * fraction),
          ),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (widget.points.isEmpty) {
      return Text(
        'No data available.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: cs.onSurface.withValues(alpha: 0.55),
        ),
      );
    }

    final maxAmount = widget.points.fold<double>(
      0,
      (maxValue, point) => math.max(maxValue, point.amount),
    );
    final totalSpend = widget.points.fold<double>(
      0,
      (sum, point) => sum + point.amount,
    );
    var peak = widget.points.first;
    for (final point in widget.points) {
      if (point.amount > peak.amount) {
        peak = point;
      }
    }

    final selectedPoint = _selectedIndex == null
        ? null
        : widget.points[_selectedIndex!.clamp(0, widget.points.length - 1)];
    final labels = _axisLabelPoints();
    final yAxisTicks = _yAxisTicks(maxAmount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 120),
          child: selectedPoint == null
              ? Text(
                  'Touch and slide to inspect monthly spend',
                  key: const ValueKey('hint-histogram'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.55),
                  ),
                )
              : Text(
                  '${selectedPoint.fullLabel}: ${formatCurrency(selectedPoint.amount)}',
                  key: ValueKey<String>(selectedPoint.monthKey),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: widget.lineColor,
                  ),
                ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 220,
          child: Row(
            children: [
              SizedBox(
                width: 44,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final chartHeight = math.max(
                      1.0,
                      constraints.maxHeight -
                          _chartTopPadding -
                          _chartBottomPadding,
                    );
                    return Stack(
                      children: yAxisTicks
                          .map((tick) {
                            final y =
                                _chartTopPadding +
                                (chartHeight * (1 - tick.fraction));
                            return Positioned(
                              top: y - 7,
                              right: 0,
                              child: Text(
                                tick.label,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      fontSize: 10,
                                      color: cs.onSurface.withValues(
                                        alpha: 0.45,
                                      ),
                                    ),
                              ),
                            );
                          })
                          .toList(growable: false),
                    );
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        widget.lineColor.withValues(alpha: 0.08),
                        cs.surface.withValues(alpha: 0.95),
                      ],
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.maxWidth;
                        return MouseRegion(
                          onHover: (event) => _updateSelection(
                            event.localPosition.dx,
                            width,
                            widget.points.length,
                          ),
                          onExit: (_) => setState(() => _selectedIndex = null),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapDown: (details) => _updateSelection(
                              details.localPosition.dx,
                              width,
                              widget.points.length,
                            ),
                            onPanStart: (details) => _updateSelection(
                              details.localPosition.dx,
                              width,
                              widget.points.length,
                            ),
                            onPanUpdate: (details) => _updateSelection(
                              details.localPosition.dx,
                              width,
                              widget.points.length,
                            ),
                            child: CustomPaint(
                              painter: _HistogramChartPainter(
                                points: widget.points,
                                maxAmount: maxAmount,
                                lineColor: widget.lineColor,
                                selectedIndex: _selectedIndex,
                              ),
                              child: const SizedBox.expand(),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.only(left: 50),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: labels
                .map(
                  (point) => Text(
                    point.label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.45),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _ChartPill(
              label: 'Total',
              value: formatCurrency(totalSpend),
              color: widget.lineColor,
            ),
            const SizedBox(width: 8),
            _ChartPill(
              label: 'Peak',
              value: '${peak.label}: ${formatCurrency(peak.amount)}',
              color: cs.secondary,
            ),
          ],
        ),
      ],
    );
  }
}

// ── Chart pill ──
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

// ── Month chart painter (daily amounts - NOT cumulative) ──
class _RobinhoodChartPainter extends CustomPainter {
  const _RobinhoodChartPainter({
    required this.points,
    required this.lineColor,
    required this.selectedIndex,
  });

  final List<DailySpendingPoint> points;
  final Color lineColor;
  final int? selectedIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final chartRect = Rect.fromLTWH(
      _chartHorizontalPadding,
      _chartTopPadding,
      size.width - (_chartHorizontalPadding * 2),
      size.height - _chartTopPadding - _chartBottomPadding,
    );

    const gridLines = 4;
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

    if (points.isEmpty) return;

    // Use daily amount (not cumulative) so graph returns to 0
    final maxAmount = math.max(
      points.fold<double>(0, (m, p) => math.max(m, p.amount)),
      1.0,
    );

    Offset pointAt(int index) {
      final xFactor = points.length == 1 ? 0.5 : index / (points.length - 1);
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

    final markerIndex = selectedIndex == null
        ? seriesPoints.length - 1
        : selectedIndex!.clamp(0, seriesPoints.length - 1);
    final markerPoint = seriesPoints[markerIndex];

    if (selectedIndex != null) {
      final crosshairPaint = Paint()
        ..color = lineColor.withValues(alpha: 0.26)
        ..strokeWidth = 1.2;
      canvas.drawLine(
        Offset(markerPoint.dx, chartRect.top),
        Offset(markerPoint.dx, chartRect.bottom),
        crosshairPaint,
      );
    }

    final glowPaint = Paint()
      ..color = lineColor.withValues(alpha: 0.20)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(markerPoint, 6, glowPaint);

    final markerPaint = Paint()..color = lineColor;
    final markerOutline = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawCircle(markerPoint, 4.5, markerPaint);
    canvas.drawCircle(markerPoint, 7, markerOutline);
  }

  @override
  bool shouldRepaint(covariant _RobinhoodChartPainter oldDelegate) {
    if (oldDelegate.lineColor != lineColor) return true;
    if (oldDelegate.selectedIndex != selectedIndex) return true;
    if (oldDelegate.points.length != points.length) return true;
    if (points.isEmpty) return false;
    return oldDelegate.points.last.amount != points.last.amount;
  }
}

// ── Histogram bar chart painter ──
class _HistogramChartPainter extends CustomPainter {
  const _HistogramChartPainter({
    required this.points,
    required this.maxAmount,
    required this.lineColor,
    required this.selectedIndex,
  });

  final List<_HistogramMonthPoint> points;
  final double maxAmount;
  final Color lineColor;
  final int? selectedIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final chartRect = Rect.fromLTWH(
      _chartHorizontalPadding,
      _chartTopPadding,
      size.width - (_chartHorizontalPadding * 2),
      size.height - _chartTopPadding - _chartBottomPadding,
    );

    const gridLines = 4;
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

    if (points.isEmpty) return;

    final safeMax = math.max(maxAmount, 1.0);
    final barWidth = chartRect.width / points.length;
    final barInset = math.min(1.2, barWidth * 0.35);

    for (var i = 0; i < points.length; i++) {
      final point = points[i];
      final normalized = (point.amount / safeMax).clamp(0.0, 1.0);
      final left = chartRect.left + (barWidth * i) + barInset;
      final right = chartRect.left + (barWidth * (i + 1)) - barInset;
      final top = chartRect.bottom - (chartRect.height * normalized);
      final rect = Rect.fromLTRB(left, top, right, chartRect.bottom);
      final radius = Radius.circular(math.min(4, math.max(1, barWidth / 3)));
      final isSelected = i == selectedIndex;
      final barPaint = Paint()
        ..color = isSelected
            ? lineColor
            : lineColor.withValues(alpha: normalized == 0 ? 0.10 : 0.28);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), barPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _HistogramChartPainter oldDelegate) {
    if (oldDelegate.lineColor != lineColor ||
        oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.maxAmount != maxAmount ||
        oldDelegate.points.length != points.length) {
      return true;
    }
    if (points.isEmpty) return false;
    return oldDelegate.points.last.amount != points.last.amount;
  }
}
