import 'package:flutter/material.dart';
import '../../../../core/theme/nexus_colors.dart';

/// Horizontal path bar: `repo › lib › utils`. Tapping a segment jumps to that
/// folder; the last segment is the current folder and is not tappable.
///
/// Paths are always laid out left-to-right, whatever the app direction.
class RepoBreadcrumb extends StatefulWidget {
  /// Label of the repository root (usually the repository name).
  final String rootLabel;

  /// Folder names from the root to the current folder.
  final List<String> segments;

  /// Called with the full path (`''` for the root) of the tapped crumb.
  final ValueChanged<String> onOpen;

  const RepoBreadcrumb({
    super.key,
    required this.rootLabel,
    required this.segments,
    required this.onOpen,
  });

  @override
  State<RepoBreadcrumb> createState() => _RepoBreadcrumbState();
}

class _RepoBreadcrumbState extends State<RepoBreadcrumb> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollToEnd();
  }

  @override
  void didUpdateWidget(covariant RepoBreadcrumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.segments.join('/') != widget.segments.join('/')) {
      _scrollToEnd();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Keeps the current (deepest) folder visible after navigating.
  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final segments = widget.segments;
    final crumbs = <Widget>[
      _Crumb(
        label: widget.rootLabel,
        icon: Icons.folder_special_rounded,
        isCurrent: segments.isEmpty,
        onTap: () => widget.onOpen(''),
      ),
    ];

    for (var i = 0; i < segments.length; i++) {
      final path = segments.sublist(0, i + 1).join('/');
      crumbs
        ..add(
          const Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: NexusColors.textSubtle,
          ),
        )
        ..add(
          _Crumb(
            label: segments[i],
            isCurrent: i == segments.length - 1,
            onTap: () => widget.onOpen(path),
          ),
        );
    }

    return Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        height: 42,
        child: SingleChildScrollView(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: crumbs),
        ),
      ),
    );
  }
}

class _Crumb extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool isCurrent;
  final VoidCallback onTap;

  const _Crumb({
    required this.label,
    required this.isCurrent,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        isCurrent ? NexusColors.textPrimary : NexusColors.primarySoft;

    return Center(
      child: Material(
        color: isCurrent
            ? NexusColors.primary.withOpacity(0.14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: isCurrent ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 15, color: color),
                  const SizedBox(width: 5),
                ],
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontFamily: 'monospace',
                      fontWeight:
                          isCurrent ? FontWeight.w700 : FontWeight.w500,
                      color: color,
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
