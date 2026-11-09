import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/format.dart';
import '../../core/settings.dart';
import '../../data/repo.dart';
import '../../models/models.dart';
import '../bills/bill_viewer.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/common.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> with DataReload {
  late DateTime _month = DateTime(today().year, today().month, 1);
  Map<String, double> _today = {}, _monthTotals = {}, _prevMonth = {};
  Map<String, double> _daily = {};
  Map<String, double> _monthly = {};
  Map<String, num> _expiry = {}, _inv = {};
  List<Map<String, Object?>> _top = [];
  List<Sale> _recent = [];
  List<BatchWithProduct> _expiring = [];
  bool _loaded = false;

  DateTime get _monthEnd => DateTime(_month.year, _month.month + 1, 1);

  @override
  void reload() async {
    final t = today();
    final prevStart = DateTime(_month.year, _month.month - 1, 1);
    final results = await Future.wait([
      Repo.salesTotals(t, t.add(const Duration(days: 1))),
      Repo.salesTotals(_month, _monthEnd),
      Repo.salesTotals(prevStart, _month),
      Repo.dailySales(_month, _monthEnd),
      Repo.monthlySales(DateTime(t.year, t.month - 5, 1)),
      Repo.expiryStats(_month, _monthEnd),
      Repo.inventoryStats(),
      Repo.topProducts(_month, _monthEnd),
      Repo.sales(limit: 6, status: 'completed'),
      Repo.expiringBatches(Settings.instance.warnDays),
    ]);
    if (!mounted) return;
    setState(() {
      _today = results[0] as Map<String, double>;
      _monthTotals = results[1] as Map<String, double>;
      _prevMonth = results[2] as Map<String, double>;
      _daily = results[3] as Map<String, double>;
      _monthly = results[4] as Map<String, double>;
      _expiry = results[5] as Map<String, num>;
      _inv = results[6] as Map<String, num>;
      _top = results[7] as List<Map<String, Object?>>;
      _recent = results[8] as List<Sale>;
      _expiring = (results[9] as List<BatchWithProduct>).take(6).toList();
      _loaded = true;
    });
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final monthTotal = _monthTotals['total'] ?? 0;
    final prevTotal = _prevMonth['total'] ?? 0;
    final isCurrentMonth = _month.year == today().year && _month.month == today().month;
    final change = prevTotal > 0 ? (monthTotal - prevTotal) / prevTotal * 100 : null;
    final soon = (_expiry['critical'] ?? 0) + (_expiry['warn'] ?? 0);
    return ListView(padding: const EdgeInsets.fromLTRB(28, 22, 28, 28), children: [
      Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$_greeting 👋', style: context.tt.headlineSmall),
            Text('${Settings.instance.shopName} · ${DateFormat('EEEE, d MMMM yyyy').format(DateTime.now())}', style: TextStyle(color: context.muted)),
          ]),
        ),
        OutlinedButton.icon(onPressed: () => Nav.go(Nav.purchases), icon: const Icon(Icons.local_shipping_outlined, size: 18), label: const Text('Stock entry')),
        const SizedBox(width: 10),
        FilledButton.icon(onPressed: () => Nav.go(Nav.billing), icon: const Icon(Icons.point_of_sale, size: 18), label: const Text('New bill  (F2)')),
      ]),
      const SizedBox(height: 20),
      LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth > 1100 ? 5 : 3;
        final w = (c.maxWidth - (cols - 1) * 14) / cols;
        final cards = [
          StatCard(
            label: "Today's sales",
            value: money0(_today['total'] ?? 0),
            sub: '${(_today['bills'] ?? 0).toInt()} bills today',
            icon: Icons.today_outlined,
            color: AppColors.brand,
            onTap: () => Nav.go(Nav.bills),
          ),
          StatCard(
            label: '${DateFormat('MMMM').format(_month)} sales',
            value: money0(monthTotal),
            sub: change == null ? '${(_monthTotals['bills'] ?? 0).toInt()} bills' : '${change >= 0 ? '▲' : '▼'} ${change.abs().toStringAsFixed(0)}% vs last month',
            icon: Icons.calendar_month_outlined,
            color: AppColors.info,
          ),
          StatCard(
            label: 'Expiries handled',
            value: '${_expiry['handled'] ?? 0}',
            sub: 'this month · ${money0(_expiry['handled_value'] ?? 0)} returned/disposed',
            icon: Icons.task_alt,
            color: AppColors.success,
            onTap: () => Nav.go(Nav.expiry),
          ),
          StatCard(
            label: 'Expiring / expired',
            value: '$soon + ${_expiry['expired'] ?? 0}',
            sub: '≤ ${Settings.instance.warnDays} days · already expired',
            icon: Icons.event_busy_outlined,
            color: (_expiry['expired'] ?? 0) > 0 ? AppColors.danger : AppColors.warning,
            onTap: () => Nav.go(Nav.expiry),
          ),
          StatCard(
            label: 'Low stock',
            value: '${_inv['low_stock'] ?? 0}',
            sub: 'medicines at reorder level',
            icon: Icons.trending_down,
            color: AppColors.violet,
            onTap: () => Nav.go(Nav.inventory),
          ),
        ];
        return Wrap(spacing: 14, runSpacing: 14, children: [for (final card in cards) SizedBox(width: w, child: card)]);
      }),
      const SizedBox(height: 16),
      SizedBox(
        height: 340,
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            flex: 5,
            child: AppCard(
              title: 'Daily sales',
              subtitle: '${DateFormat('MMMM yyyy').format(_month)} · total ${money0(monthTotal)}',
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  tooltip: 'Previous month',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () {
                    setState(() => _month = DateTime(_month.year, _month.month - 1, 1));
                    reload();
                  },
                ),
                IconButton(
                  tooltip: 'Next month',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: isCurrentMonth
                      ? null
                      : () {
                          setState(() => _month = DateTime(_month.year, _month.month + 1, 1));
                          reload();
                        },
                ),
              ]),
              child: _dailyChart(),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(flex: 3, child: AppCard(title: 'Monthly sales', subtitle: 'Last 6 months', child: _monthlyChart())),
        ]),
      ),
      const SizedBox(height: 16),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: _topCard()),
        const SizedBox(width: 16),
        Expanded(child: _recentCard()),
        const SizedBox(width: 16),
        Expanded(child: _expiryCard()),
      ]),
    ]);
  }

  // ------------------------------------------------------------ charts

  FlTitlesData _titles(Widget Function(double, TitleMeta) bottom, double maxY) => FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 52,
            interval: _niceInterval(maxY),
            getTitlesWidget: (v, m) => v == m.max && v != 0
                ? const SizedBox.shrink()
                : Text(moneyShort(v), style: TextStyle(fontSize: 11, color: context.muted)),
          ),
        ),
        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 24, getTitlesWidget: bottom)),
      );

  double _niceInterval(double maxY) {
    if (maxY <= 0) return 100;
    final raw = maxY / 4;
    final mag = [1, 2, 2.5, 5, 10, 20, 25, 50, 100, 200, 250, 500, 1000, 2000, 2500, 5000, 10000, 20000, 25000, 50000, 100000, 200000, 500000];
    return mag.firstWhere((m) => m >= raw, orElse: () => raw).toDouble();
  }

  FlGridData _grid(double maxY) => FlGridData(
        drawVerticalLine: false,
        horizontalInterval: _niceInterval(maxY),
        getDrawingHorizontalLine: (_) => FlLine(color: context.border, strokeWidth: 1),
      );

  Widget _dailyChart() {
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final values = [for (var d = 1; d <= days; d++) _daily[isoDate(DateTime(_month.year, _month.month, d))] ?? 0.0];
    final maxV = values.fold(0.0, (a, b) => a > b ? a : b);
    final maxY = maxV <= 0 ? 1000.0 : maxV * 1.15;
    final t = today();
    final color = context.cs.primary;
    return BarChart(
      BarChartData(
        maxY: maxY,
        minY: 0,
        gridData: _grid(maxY),
        borderData: FlBorderData(show: true, border: Border(bottom: BorderSide(color: context.border))),
        titlesData: _titles((v, m) {
          final d = v.toInt() + 1;
          if (d != 1 && d % 5 != 0 && d != days) return const SizedBox.shrink();
          return Padding(padding: const EdgeInsets.only(top: 6), child: Text('$d', style: TextStyle(fontSize: 11, color: context.muted)));
        }, maxY),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => const Color(0xFF1F2937),
            tooltipBorderRadius: BorderRadius.circular(8),
            getTooltipItem: (g, gi, rod, ri) => BarTooltipItem(
              '${DateFormat('d MMM, EEE').format(DateTime(_month.year, _month.month, g.x + 1))}\n',
              const TextStyle(color: Colors.white70, fontSize: 11),
              children: [TextSpan(text: money(rod.toY), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13))],
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < days; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: values[i],
                width: 9,
                color: DateTime(_month.year, _month.month, i + 1).isAfter(t) ? color.withValues(alpha: 0.25) : color,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ]),
        ],
      ),
    );
  }

  Widget _monthlyChart() {
    final t = today();
    final months = [for (var i = 5; i >= 0; i--) DateTime(t.year, t.month - i, 1)];
    final values = [for (final m in months) _monthly[DateFormat('yyyy-MM').format(m)] ?? 0.0];
    final maxV = values.fold(0.0, (a, b) => a > b ? a : b);
    final maxY = maxV <= 0 ? 1000.0 : maxV * 1.15;
    final color = context.cs.primary;
    return BarChart(
      BarChartData(
        maxY: maxY,
        minY: 0,
        gridData: _grid(maxY),
        borderData: FlBorderData(show: true, border: Border(bottom: BorderSide(color: context.border))),
        titlesData: _titles(
          (v, m) => Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(DateFormat('MMM').format(months[v.toInt()]), style: TextStyle(fontSize: 11, color: context.muted)),
          ),
          maxY,
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => const Color(0xFF1F2937),
            tooltipBorderRadius: BorderRadius.circular(8),
            getTooltipItem: (g, gi, rod, ri) => BarTooltipItem(
              '${DateFormat('MMMM yyyy').format(months[g.x])}\n',
              const TextStyle(color: Colors.white70, fontSize: 11),
              children: [TextSpan(text: money(rod.toY), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13))],
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < months.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: values[i],
                width: 22,
                color: i == months.length - 1 ? color : color.withValues(alpha: 0.55),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ]),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ lists

  Widget _topCard() {
    final maxV = _top.isEmpty ? 1.0 : (_top.first['total'] as num).toDouble();
    return AppCard(
      title: 'Top medicines',
      subtitle: DateFormat('MMMM').format(_month),
      child: _top.isEmpty
          ? Padding(padding: const EdgeInsets.all(20), child: Text('No sales yet', style: TextStyle(color: context.muted)))
          : Column(children: [
              for (final r in _top)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(r['product_name'] as String, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                      Text(money0((r['total'] as num).toDouble()), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ]),
                    const SizedBox(height: 4),
                    Row(children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: (r['total'] as num).toDouble() / maxV,
                            minHeight: 5,
                            backgroundColor: context.cs.surfaceContainerHigh,
                            color: context.cs.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        fmtQty((r['units'] as num).toInt(), (r['pack_size'] as num?)?.toInt() ?? 1, '${r['unit_name']}', '${r['pack_name']}'),
                        style: TextStyle(fontSize: 11.5, color: context.muted),
                      ),
                    ]),
                  ]),
                ),
            ]),
    );
  }

  Widget _recentCard() => AppCard(
        title: 'Recent bills',
        trailing: TextButton(onPressed: () => Nav.go(Nav.bills), child: const Text('View all')),
        child: _recent.isEmpty
            ? Padding(padding: const EdgeInsets.all(20), child: Text('No bills yet — press F2 to start one', style: TextStyle(color: context.muted)))
            : Column(children: [
                for (final s in _recent)
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => showBillViewer(context, saleId: s.id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
                      child: Row(children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: context.cs.primary.withValues(alpha: 0.1),
                          child: Icon(Icons.receipt_outlined, size: 16, color: context.cs.primary),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${s.billNo} · ${s.customerName.isEmpty ? 'Walk-in' : s.customerName}', style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                            Text('${fmtDateTime(s.createdAt)} · ${s.itemCount} item${s.itemCount == 1 ? '' : 's'}', style: TextStyle(fontSize: 11.5, color: context.muted)),
                          ]),
                        ),
                        Text(money0(s.grandTotal), style: const TextStyle(fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ),
              ]),
      );

  Widget _expiryCard() => AppCard(
        title: 'Expiry watch',
        subtitle: 'Next ${Settings.instance.warnDays} days',
        trailing: TextButton(onPressed: () => Nav.go(Nav.expiry), child: const Text('Manage')),
        child: _expiring.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(20),
                child: Row(children: [
                  const Icon(Icons.verified_outlined, color: AppColors.success),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Nothing expiring soon', style: TextStyle(color: context.muted))),
                ]),
              )
            : Column(children: [
                for (final r in _expiring)
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => Nav.openProduct(r.product.id!),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
                      child: Row(children: [
                        Icon(r.batch.isExpired ? Icons.block : Icons.hourglass_bottom, size: 20, color: expiryColor(context, r.batch.expiry)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(r.product.name, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                            Text('${r.batch.batchNo} · ${r.product.qty(r.batch.qty)}', style: TextStyle(fontSize: 11.5, color: context.muted)),
                          ]),
                        ),
                        ExpiryBadge(r.batch.expiry, small: true),
                      ]),
                    ),
                  ),
              ]),
      );
}
