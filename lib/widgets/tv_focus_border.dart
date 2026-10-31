import 'package:flutter/material.dart';
import 'package:frosty/utils/tv.dart';

/// Adds a D-pad focus ring around a focusable child on TV devices.
///
/// The wrapper listens to its descendants through an ancestor [Focus] node
/// instead of stealing focus itself. That keeps the child's existing focus
/// handling (for example an [InkWell]'s tap action) intact while still letting
/// the card show a clear focus indicator at couch distance.
class TvFocusBorder extends StatefulWidget {
  final Widget child;
  final BorderRadius borderRadius;

  /// Overrides TV detection. Intended for tests and previews.
  final bool? enabled;

  const TvFocusBorder({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.enabled,
  });

  @override
  State<TvFocusBorder> createState() => _TvFocusBorderState();
}

class _TvFocusBorderState extends State<TvFocusBorder> {
  bool _focused = false;

  void _handleFocusChange(bool focused) {
    if (!mounted || focused == _focused) return;

    setState(() => _focused = focused);

    if (!focused) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_focused || Scrollable.maybeOf(context) == null) return;

      Scrollable.ensureVisible(
        context,
        alignment: 0.5,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled ?? isTv;
    if (!enabled) return widget.child;

    final focusColor = Theme.of(context).colorScheme.primary;

    return Focus(
      canRequestFocus: false,
      onFocusChange: _handleFocusChange,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius,
          border: Border.all(
            color: _focused ? focusColor : Colors.transparent,
            width: 2,
          ),
          boxShadow: _focused
              ? [
                  BoxShadow(
                    color: focusColor.withValues(alpha: 0.35),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: widget.child,
      ),
    );
  }
}
