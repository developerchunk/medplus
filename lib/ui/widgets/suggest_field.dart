import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// A text field that shows live suggestions from the inventory as you type.
///
/// Keyboard: ↑/↓ move, Enter/Tab pick, Esc closes. When no suggestion is
/// open, Enter calls [onSubmitted] so forms can jump to the next field.
class SuggestField<T extends Object> extends StatefulWidget {
  const SuggestField({
    super.key,
    required this.search,
    required this.itemBuilder,
    required this.display,
    this.controller,
    this.focusNode,
    this.onSelected,
    this.onSubmitted,
    this.onChanged,
    this.label,
    this.hint,
    this.prefixIcon,
    this.suffix,
    this.showOnFocus = false,
    this.overlayWidth,
    this.overlayMaxHeight = 320,
    this.autofocus = false,
    this.enabled = true,
    this.errorText,
    this.helperText,
    this.style,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    this.emptyBuilder,
    this.headerBuilder,
    this.selectAllOnFocus = false,
    this.dense = false,
    this.textAlign = TextAlign.start,
    this.keyboardType,
  });

  final Future<List<T>> Function(String query) search;
  final Widget Function(BuildContext context, T item, bool highlighted) itemBuilder;
  final String Function(T item) display;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final ValueChanged<T>? onSelected;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final String? label;
  final String? hint;
  final Widget? prefixIcon;
  final Widget? suffix;
  final bool showOnFocus;
  final double? overlayWidth;
  final double overlayMaxHeight;
  final bool autofocus;
  final bool enabled;
  final String? errorText;
  final String? helperText;
  final TextStyle? style;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;
  final WidgetBuilder? emptyBuilder;
  final Widget Function(BuildContext context, int count)? headerBuilder;
  final bool selectAllOnFocus;
  final bool dense;
  final TextAlign textAlign;
  final TextInputType? keyboardType;

  @override
  State<SuggestField<T>> createState() => _SuggestFieldState<T>();
}

class _SuggestFieldState<T extends Object> extends State<SuggestField<T>> {
  late TextEditingController _ctrl;
  late FocusNode _focus;
  bool _ownCtrl = false, _ownFocus = false;
  final _portal = OverlayPortalController();
  final _link = LayerLink();
  final _scroll = ScrollController();
  List<T> _items = [];
  int _highlight = 0;
  int _callId = 0;
  bool _suppress = false;
  bool _typed = false;
  bool _openUp = false;
  bool _searched = false;
  String _lastText = '';
  double _fieldWidth = 300;
  final _itemKeys = <int, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    _ownCtrl = widget.controller == null;
    _ownFocus = widget.focusNode == null;
    _ctrl = widget.controller ?? TextEditingController();
    _focus = widget.focusNode ?? FocusNode();
    _ctrl.addListener(_onText);
    _focus.addListener(_onFocus);
    _lastText = _ctrl.text;
  }

  @override
  void didUpdateWidget(covariant SuggestField<T> old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller && widget.controller != null) {
      _ctrl.removeListener(_onText);
      if (_ownCtrl) _ctrl.dispose();
      _ctrl = widget.controller!;
      _ownCtrl = false;
      _ctrl.addListener(_onText);
      _lastText = _ctrl.text;
    }
    if (old.focusNode != widget.focusNode && widget.focusNode != null) {
      _focus.removeListener(_onFocus);
      if (_ownFocus) _focus.dispose();
      _focus = widget.focusNode!;
      _ownFocus = false;
      _focus.addListener(_onFocus);
    }
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onText);
    _focus.removeListener(_onFocus);
    if (_ownCtrl) _ctrl.dispose();
    if (_ownFocus) _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onText() {
    if (_suppress) return;
    if (_ctrl.text == _lastText) return;
    _lastText = _ctrl.text;
    if (_focus.hasFocus) {
      _typed = true;
      _refresh(_ctrl.text);
    }
  }

  void _onFocus() {
    if (_focus.hasFocus) {
      _typed = false;
      if (widget.selectAllOnFocus && _ctrl.text.isNotEmpty) {
        _ctrl.selection = TextSelection(baseOffset: 0, extentOffset: _ctrl.text.length);
      }
      if (widget.showOnFocus) _refresh('', highlightText: _ctrl.text);
    } else {
      _hide();
    }
  }

  Future<void> _refresh(String q, {String? highlightText}) async {
    final id = ++_callId;
    final items = await widget.search(q);
    if (!mounted || id != _callId || !_focus.hasFocus) return;
    var hi = 0;
    if (highlightText != null && highlightText.isNotEmpty) {
      final i = items.indexWhere((e) => widget.display(e).toLowerCase() == highlightText.toLowerCase());
      if (i >= 0) hi = i;
    }
    setState(() {
      _items = items;
      _highlight = hi;
      _searched = true;
      _itemKeys.clear();
    });
    final showEmpty = items.isEmpty && widget.emptyBuilder != null && q.trim().isNotEmpty;
    if (items.isNotEmpty || showEmpty) {
      _show();
      if (hi > 0) WidgetsBinding.instance.addPostFrameCallback((_) => _ensureVisible());
    } else {
      _hide();
    }
  }

  void _show() {
    final box = context.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      final pos = box.localToGlobal(Offset.zero);
      final screen = MediaQuery.sizeOf(context).height;
      final below = screen - pos.dy - box.size.height;
      _openUp = below < widget.overlayMaxHeight + 16 && pos.dy > below;
    }
    if (!_portal.isShowing) _portal.show();
  }

  void _hide() {
    if (_portal.isShowing) _portal.hide();
  }

  void _select(T item) {
    final s = widget.display(item);
    _suppress = true;
    _ctrl.value = TextEditingValue(text: s, selection: TextSelection.collapsed(offset: s.length));
    _lastText = s;
    _suppress = false;
    _typed = false;
    _hide();
    widget.onSelected?.call(item);
  }

  void _move(int delta) {
    if (_items.isEmpty) return;
    setState(() => _highlight = (_highlight + delta).clamp(0, _items.length - 1));
    _ensureVisible();
  }

  void _ensureVisible() {
    final ctx = _itemKeys[_highlight]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd, duration: const Duration(milliseconds: 80));
      Scrollable.ensureVisible(ctx, alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart, duration: const Duration(milliseconds: 80));
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final open = _portal.isShowing;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowDown) {
      if (!open) {
        _refresh(_typed ? _ctrl.text : '', highlightText: _ctrl.text);
        return KeyEventResult.handled;
      }
      _move(1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp && open) {
      _move(-1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.pageDown && open) {
      _move(6);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.pageUp && open) {
      _move(-6);
      return KeyEventResult.handled;
    }
    if ((k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) && open && _items.isNotEmpty) {
      // A list that opened on focus shouldn't hijack Enter: without typing, only accept
      // the suggestion that matches what's already in the field, else just move on.
      final hi = _items[_highlight];
      final matchesText = widget.display(hi).toLowerCase() == _ctrl.text.trim().toLowerCase();
      if (_typed || matchesText) {
        _select(hi);
      } else {
        _hide();
        widget.onSubmitted?.call(_ctrl.text);
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.tab && open && _items.isNotEmpty && _typed && !HardwareKeyboard.instance.isShiftPressed) {
      _select(_items[_highlight]);
      return KeyEventResult.ignored; // let focus move on
    }
    if (k == LogicalKeyboardKey.escape && open) {
      _hide();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _overlay(BuildContext context) {
    final cs = context.cs;
    final width = widget.overlayWidth ?? _fieldWidth.clamp(260.0, 900.0);
    final showEmpty = _items.isEmpty && _searched && widget.emptyBuilder != null;
    final panel = TextFieldTapRegion(
      child: Material(
        elevation: 10,
        shadowColor: Colors.black.withValues(alpha: 0.25),
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Container(
          width: width,
          constraints: BoxConstraints(maxHeight: widget.overlayMaxHeight),
          decoration: BoxDecoration(border: Border.all(color: cs.outlineVariant), borderRadius: BorderRadius.circular(12)),
          child: showEmpty
              ? widget.emptyBuilder!(context)
              : Column(mainAxisSize: MainAxisSize.min, children: [
                  if (widget.headerBuilder != null) widget.headerBuilder!(context, _items.length),
                  Flexible(
                    child: ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      shrinkWrap: true,
                      itemCount: _items.length,
                      itemBuilder: (context, i) {
                        final key = _itemKeys.putIfAbsent(i, () => GlobalKey());
                        final hi = i == _highlight;
                        return InkWell(
                          key: key,
                          onTap: () => _select(_items[i]),
                          onHover: (h) {
                            if (h && _highlight != i) setState(() => _highlight = i);
                          },
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: hi ? cs.primary.withValues(alpha: context.isDark ? 0.18 : 0.08) : null,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: widget.itemBuilder(context, _items[i], hi),
                          ),
                        );
                      },
                    ),
                  ),
                ]),
        ),
      ),
    );
    return CompositedTransformFollower(
      link: _link,
      showWhenUnlinked: false,
      targetAnchor: _openUp ? Alignment.topLeft : Alignment.bottomLeft,
      followerAnchor: _openUp ? Alignment.bottomLeft : Alignment.topLeft,
      offset: Offset(0, _openUp ? -4 : 4),
      child: Align(alignment: _openUp ? Alignment.bottomLeft : Alignment.topLeft, child: panel),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth.isFinite) _fieldWidth = c.maxWidth;
      return CompositedTransformTarget(
        link: _link,
        child: OverlayPortal(
          controller: _portal,
          overlayChildBuilder: _overlay,
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: _onKey,
            child: TextField(
              controller: _ctrl,
              focusNode: _focus,
              autofocus: widget.autofocus,
              enabled: widget.enabled,
              style: widget.style,
              textAlign: widget.textAlign,
              keyboardType: widget.keyboardType,
              inputFormatters: widget.inputFormatters,
              textCapitalization: widget.textCapitalization,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              decoration: InputDecoration(
                labelText: widget.label,
                hintText: widget.hint,
                prefixIcon: widget.prefixIcon,
                suffixIcon: widget.suffix,
                errorText: widget.errorText,
                helperText: widget.helperText,
                contentPadding: widget.dense ? const EdgeInsets.symmetric(horizontal: 10, vertical: 9) : null,
              ),
            ),
          ),
        ),
      );
    });
  }
}

/// Standard two-line suggestion row.
class SuggestTile extends StatelessWidget {
  const SuggestTile({super.key, required this.title, this.subtitle, this.leading, this.trailing, this.badges = const []});
  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final List<Widget> badges;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Row(children: [
        if (leading != null) ...[leading!, const SizedBox(width: 10)],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Flexible(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5))),
              for (final b in badges) ...[const SizedBox(width: 6), b],
            ]),
            if (subtitle != null && subtitle!.isNotEmpty)
              Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: context.muted)),
          ]),
        ),
        if (trailing != null) ...[const SizedBox(width: 10), trailing!],
      ]),
    );
  }
}
