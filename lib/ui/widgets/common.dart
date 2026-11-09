import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/db.dart';
import '../../core/format.dart';
import '../../core/settings.dart';
import '../../models/models.dart';
import '../theme.dart';

// ------------------------------------------------------------------ page layout

class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.subtitle, this.actions = const [], this.bottom});
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: context.tt.headlineSmall),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: TextStyle(color: context.muted, fontSize: 13)),
              ],
            ]),
          ),
          ...actions.expand((a) => [const SizedBox(width: 10), a]),
        ]),
        if (bottom != null) ...[const SizedBox(height: 14), bottom!],
      ]),
    );
  }
}

class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(18), this.title, this.trailing, this.subtitle, this.color});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color,
      child: Padding(
        padding: padding,
        child: title == null
            ? child
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title!, style: context.tt.titleMedium),
                      if (subtitle != null) Text(subtitle!, style: TextStyle(color: context.muted, fontSize: 12)),
                    ]),
                  ),
                  ?trailing,
                ]),
                const SizedBox(height: 14),
                Flexible(fit: FlexFit.loose, child: child),
              ]),
      ),
    );
  }
}

class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.label, required this.value, required this.icon, required this.color, this.sub, this.onTap});
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? sub;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 21),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: TextStyle(color: context.muted, fontSize: 12.5, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.4)),
                ),
                if (sub != null) ...[
                  const SizedBox(height: 2),
                  Text(sub!, style: TextStyle(color: context.muted, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ badges

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, required this.color, this.icon, this.solid = false, this.small = false});
  final String text;
  final Color color;
  final IconData? icon;
  final bool solid;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 5 : 7, vertical: small ? 1 : 2.5),
      decoration: BoxDecoration(
        color: solid ? color : color.withValues(alpha: context.isDark ? 0.22 : 0.11),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: small ? 11 : 13, color: solid ? Colors.white : color), const SizedBox(width: 3)],
        Text(text,
            style: TextStyle(
                fontSize: small ? 10.5 : 11.5, fontWeight: FontWeight.w600, color: solid ? Colors.white : color, height: 1.3)),
      ]),
    );
  }
}

class RxBadge extends StatelessWidget {
  const RxBadge(this.product, {super.key, this.small = true});
  final Product product;
  final bool small;
  @override
  Widget build(BuildContext context) {
    if (!product.needsPrescription) return const SizedBox.shrink();
    final label = product.isAntibiotic ? 'Antibiotic · Rx' : product.schedule.isNotEmpty ? 'Sch ${product.schedule} · Rx' : 'Rx';
    return Tooltip(message: product.warningText, child: Pill(label, color: AppColors.rx, small: small));
  }
}

enum ExpiryLevel { expired, critical, warn, ok }

ExpiryLevel expiryLevel(DateTime exp) {
  final d = daysUntil(exp);
  final s = Settings.instance;
  if (d < 0) return ExpiryLevel.expired;
  if (d <= s.criticalDays) return ExpiryLevel.critical;
  if (d <= s.warnDays) return ExpiryLevel.warn;
  return ExpiryLevel.ok;
}

Color expiryColor(BuildContext context, DateTime exp) => switch (expiryLevel(exp)) {
      ExpiryLevel.expired => AppColors.danger,
      ExpiryLevel.critical => AppColors.warning,
      ExpiryLevel.warn => AppColors.caution,
      ExpiryLevel.ok => context.muted,
    };

class ExpiryBadge extends StatelessWidget {
  const ExpiryBadge(this.expiry, {super.key, this.showPhrase = false, this.small = false});
  final DateTime expiry;
  final bool showPhrase;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final lvl = expiryLevel(expiry);
    final color = expiryColor(context, expiry);
    final text = showPhrase && lvl != ExpiryLevel.ok ? '${fmtExpiry(expiry)} · ${expiryPhrase(expiry)}' : fmtExpiry(expiry);
    if (lvl == ExpiryLevel.ok) {
      return Text(text, style: TextStyle(color: color, fontSize: small ? 12 : 13, fontWeight: FontWeight.w500));
    }
    return Tooltip(
      message: expiryPhrase(expiry),
      child: Pill(text, color: color, icon: lvl == ExpiryLevel.expired ? Icons.block : Icons.schedule, small: small),
    );
  }
}

// ------------------------------------------------------------------ misc

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: context.cs.primary.withValues(alpha: 0.08), shape: BoxShape.circle),
            child: Icon(icon, size: 30, color: context.cs.primary),
          ),
          const SizedBox(height: 14),
          Text(title, style: context.tt.titleMedium, textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Text(message!, style: TextStyle(color: context.muted), textAlign: TextAlign.center),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]),
      ),
    );
  }
}

class SearchBox extends StatelessWidget {
  const SearchBox({super.key, required this.onChanged, this.hint = 'Search…', this.width = 320, this.controller, this.autofocus = false});
  final ValueChanged<String> onChanged;
  final String hint;
  final double width;
  final TextEditingController? controller;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        autofocus: autofocus,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.search, size: 20),
          fillColor: context.cs.surface,
        ),
      ),
    );
  }
}

/// Header + rows table used by list screens. Columns size by flex or fixed width.
class TableCol {
  final String label;
  final double flex;
  final double? width;
  final bool right;
  const TableCol(this.label, {this.flex = 1, this.width, this.right = false});
}

class SimpleTable extends StatelessWidget {
  const SimpleTable({super.key, required this.columns, required this.rowCount, required this.cells, this.onTap, this.rowColor, this.selected});
  final List<TableCol> columns;
  final int rowCount;
  final List<Widget> Function(int index) cells;
  final void Function(int index)? onTap;
  final Color? Function(int index)? rowColor;
  final int? selected;

  Widget _row(BuildContext context, List<Widget> children, {bool header = false}) {
    return Row(children: [
      for (var i = 0; i < columns.length; i++)
        () {
          final c = columns[i];
          final child = Align(alignment: c.right ? Alignment.centerRight : Alignment.centerLeft, child: children[i]);
          final padded = Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: child);
          return c.width != null ? SizedBox(width: c.width, child: padded) : Expanded(flex: (c.flex * 10).round(), child: padded);
        }(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final headerStyle = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: context.muted, letterSpacing: 0.4);
    return Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: context.cs.surfaceContainer, border: Border(bottom: BorderSide(color: context.border))),
        child: _row(context, [for (final c in columns) Text(c.label.toUpperCase(), style: headerStyle, maxLines: 1, overflow: TextOverflow.ellipsis)], header: true),
      ),
      Expanded(
        child: ListView.separated(
          itemCount: rowCount,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) => Material(
            color: selected == i ? context.cs.primary.withValues(alpha: 0.08) : rowColor?.call(i) ?? Colors.transparent,
            child: InkWell(
              onTap: onTap == null ? null : () => onTap!(i),
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11), child: _row(context, cells(i))),
            ),
          ),
        ),
      ),
    ]);
  }
}

// ------------------------------------------------------------------ dialogs & feedback

void showSnack(BuildContext context, String message, {bool error = false, SnackBarAction? action}) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: Row(children: [
      Icon(error ? Icons.error_outline : Icons.check_circle_outline, color: Colors.white, size: 20),
      const SizedBox(width: 10),
      Expanded(child: Text(message)),
    ]),
    backgroundColor: error ? AppColors.danger : const Color(0xFF1F2937),
    action: action,
    duration: Duration(seconds: error ? 5 : 3),
  ));
}

Future<bool> confirm(BuildContext context, {required String title, required String message, String confirmLabel = 'Confirm', bool destructive = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: Text(message)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: AppColors.danger) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return r ?? false;
}

Future<String?> promptText(BuildContext context, {required String title, String label = '', String initial = '', String confirmLabel = 'OK', bool required = false}) async {
  final ctrl = TextEditingController(text: initial);
  final r = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 400,
        child: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
          onSubmitted: (v) {
            if (!required || v.trim().isNotEmpty) Navigator.pop(ctx, v.trim());
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (!required || ctrl.text.trim().isNotEmpty) Navigator.pop(ctx, ctrl.text.trim());
          },
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return r;
}

/// A modal side-sheet-ish dialog with header and footer used for forms.
class FormDialog extends StatelessWidget {
  const FormDialog({super.key, required this.title, required this.child, required this.actions, this.width = 560, this.subtitle, this.icon});
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget child;
  final List<Widget> actions;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width, maxHeight: MediaQuery.sizeOf(context).height * 0.9),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 12, 12),
            child: Row(children: [
              if (icon != null) ...[
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: context.cs.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(9)),
                  child: Icon(icon, color: context.cs.primary, size: 20),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: context.tt.titleLarge),
                  if (subtitle != null) Text(subtitle!, style: TextStyle(color: context.muted, fontSize: 12.5)),
                ]),
              ),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close), tooltip: 'Close (Esc)'),
            ]),
          ),
          const Divider(),
          Flexible(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(22, 18, 22, 18), child: child)),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 14),
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: actions.expand((a) => [const SizedBox(width: 10), a]).skip(1).toList()),
          ),
        ]),
      ),
    );
  }
}

/// Lays out form fields in rows with consistent spacing.
class FieldRow extends StatelessWidget {
  const FieldRow({super.key, required this.children, this.flex});
  final List<Widget> children;
  final List<int>? flex;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(flex: flex?[i] ?? 1, child: children[i]),
        ],
      ]),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10, top: 4),
        child: Row(children: [
          Text(text.toUpperCase(), style: TextStyle(fontSize: 11.5, letterSpacing: 0.6, fontWeight: FontWeight.w700, color: context.muted)),
          const SizedBox(width: 10),
          const Expanded(child: Divider()),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
        ]),
      );
}

final decimalInput = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];

/// Batch numbers are always capitals: typing "px77" shows "PX77".
class UpperCaseInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}

final upperInput = <TextInputFormatter>[UpperCaseInputFormatter()];

/// GST % that accepts any rate (e.g. 2.5, 3) with a quick-pick menu of the common slabs.
class GstField extends StatefulWidget {
  const GstField({super.key, required this.value, required this.onChanged, this.label = 'GST', this.focusNode, this.onSubmitted});
  final double value;
  final ValueChanged<double> onChanged;
  final String label;
  final FocusNode? focusNode;
  final VoidCallback? onSubmitted;

  static const presets = [0.0, 5.0, 12.0, 18.0, 28.0];

  @override
  State<GstField> createState() => _GstFieldState();
}

class _GstFieldState extends State<GstField> {
  late final _ctrl = TextEditingController(text: trimNum(widget.value));
  String? _error;

  @override
  void didUpdateWidget(covariant GstField old) {
    super.didUpdateWidget(old);
    if (widget.value != parseNum(_ctrl.text, -1)) _ctrl.text = trimNum(widget.value);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _set(String v) {
    final n = double.tryParse(v.trim());
    setState(() => _error = n == null || n < 0 || n > 100 ? '0–100' : null);
    if (_error == null) widget.onChanged(n!);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      focusNode: widget.focusNode,
      inputFormatters: decimalInput,
      onChanged: _set,
      onSubmitted: widget.onSubmitted == null ? null : (_) => widget.onSubmitted!(),
      decoration: InputDecoration(
        labelText: widget.label,
        suffixText: '%',
        errorText: _error,
        suffixIcon: ExcludeFocus(
          child: PopupMenuButton<double>(
            tooltip: 'Common GST rates',
            icon: const Icon(Icons.arrow_drop_down),
            onSelected: (r) {
              _ctrl.text = trimNum(r);
              _set(_ctrl.text);
            },
            itemBuilder: (_) => [for (final r in GstField.presets) PopupMenuItem(value: r, child: Text('${trimNum(r)} %'))],
          ),
        ),
      ),
    );
  }
}
final intInput = [FilteringTextInputFormatter.digitsOnly];

/// Enter-to-next-field for forms. A form lists its fields in [flowOrder] (only the ones
/// currently shown); Enter on a field moves to the next one, and on the last one calls [onFlowDone].
mixin EnterFlow<T extends StatefulWidget> on State<T> {
  final Map<String, FocusNode> _flowNodes = {};

  /// Focus node for a named field (created on first use, disposed with the form).
  FocusNode fn(String key) => _flowNodes.putIfAbsent(key, () => FocusNode(debugLabel: key));

  /// Field keys in Enter order; include only fields that are visible right now.
  List<String> get flowOrder;

  /// Called on Enter in the last field (usually save / add).
  void onFlowDone();

  /// A text field wired into the Enter flow under [key]. Multi-line fields still move on
  /// with Enter (Shift+Enter is not needed for these short notes).
  Widget flowField(
    String key,
    TextEditingController controller, {
    String? label,
    String? hint,
    String? helper,
    String? error,
    String? prefix,
    String? suffix,
    InputDecoration? decoration,
    List<TextInputFormatter>? formatters,
    bool autofocus = false,
    bool enabled = true,
    int maxLines = 1,
    TextCapitalization caps = TextCapitalization.none,
    ValueChanged<String>? onChanged,
  }) =>
      TextField(
        controller: controller,
        focusNode: fn(key),
        autofocus: autofocus,
        enabled: enabled,
        maxLines: maxLines,
        minLines: 1,
        keyboardType: TextInputType.text,
        textCapitalization: caps,
        inputFormatters: formatters,
        onChanged: onChanged,
        onSubmitted: (_) => advance(key),
        decoration: decoration ??
            InputDecoration(labelText: label, hintText: hint, helperText: helper, errorText: error, prefixText: prefix, suffixText: suffix),
      );

  void advance(String from) {
    final order = flowOrder;
    final i = order.indexOf(from);
    if (i < 0 || i == order.length - 1) {
      onFlowDone();
    } else {
      fn(order[i + 1]).requestFocus();
    }
  }

  @override
  void dispose() {
    for (final n in _flowNodes.values) {
      n.dispose();
    }
    super.dispose();
  }
}

/// Calls [reload] on start and whenever any data changes (see [notifyDataChanged]).
mixin DataReload<T extends StatefulWidget> on State<T> {
  void reload();

  @override
  void initState() {
    super.initState();
    dataVersion.addListener(_onData);
    reload();
  }

  void _onData() {
    if (mounted) reload();
  }

  @override
  void dispose() {
    dataVersion.removeListener(_onData);
    super.dispose();
  }
}
