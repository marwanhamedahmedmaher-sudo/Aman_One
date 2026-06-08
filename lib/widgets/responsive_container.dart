import 'package:flutter/material.dart';

/// Constrains its child to a maximum width and centers it on wide screens
/// (e.g. tablets). On narrow screens (< [maxWidth]) this is effectively a
/// no-op — [ConstrainedBox] with only a `maxWidth` passes tighter parent
/// constraints through unchanged.
///
/// The pilot-era "quick win" responsive wrapper: every top-level screen body
/// is wrapped with it so phone layouts don't stretch uncomfortably across a
/// tablet's full screen width. A proper adaptive/master-detail tablet layout
/// is tracked separately — see P1-15 in `CLAUDE.md`.
class ResponsiveContainer extends StatelessWidget {
  /// Default reading-column width. Tuned for single-column forms on a 10"
  /// tablet; wider screens will still center the content with background on
  /// either side.
  static const double defaultMaxWidth = 640;

  final Widget child;
  final double maxWidth;

  const ResponsiveContainer({
    super.key,
    required this.child,
    this.maxWidth = defaultMaxWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
