import 'package:flutter/material.dart';
import '../../../../core/theme/nexus_colors.dart';
import '../../../../core/widgets/glass_panel.dart';

/// Top bar shown instead of the normal header while entries are selected:
/// cancel (✕), counter and "select all".
class RepoSelectionHeader extends StatelessWidget {
  final int count;
  final bool allSelected;
  final VoidCallback onClose;
  final VoidCallback onSelectAll;

  const RepoSelectionHeader({
    super.key,
    required this.count,
    required this.allSelected,
    required this.onClose,
    required this.onSelectAll,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
      decoration: BoxDecoration(
        color: NexusColors.bgDeep.withOpacity(0.55),
        border: const Border(
          bottom: BorderSide(color: NexusColors.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'إلغاء التحديد',
            onPressed: onClose,
            icon: const Icon(
              Icons.close_rounded,
              color: NexusColors.textSecondary,
            ),
          ),
          Expanded(
            child: Text(
              '$count محدد',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: NexusColors.textPrimary,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: allSelected ? null : onSelectAll,
            icon: const Icon(Icons.select_all_rounded, size: 18),
            label: const Text('تحديد الكل'),
            style: TextButton.styleFrom(
              foregroundColor: NexusColors.primarySoft,
              disabledForegroundColor: NexusColors.textSubtle,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom action bar of the selection mode.
///
/// Every action is enabled by passing its callback. A `null` callback shows
/// the action disabled with its tooltip: rename needs exactly one selected
/// entry, the others are only disabled while nothing allows them.
class RepoSelectionBar extends StatelessWidget {
  final VoidCallback? onDelete;
  final VoidCallback? onMove;
  final VoidCallback? onRename;
  final VoidCallback? onDownload;

  const RepoSelectionBar({
    super.key,
    required this.onDelete,
    this.onMove,
    this.onRename,
    this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: NexusColors.bgDeep.withOpacity(0.92),
        border: const Border(top: BorderSide(color: NexusColors.borderSubtle)),
      ),
      child: Row(
        children: [
          _BarAction(
            key: const ValueKey('selection_delete'),
            icon: Icons.delete_outline_rounded,
            label: 'حذف',
            color: NexusColors.roseSoft,
            onTap: onDelete,
          ),
          _BarAction(
            key: const ValueKey('selection_move'),
            icon: Icons.drive_file_move_outlined,
            label: 'نقل',
            onTap: onMove,
            disabledHint: 'النقل غير متاح الآن',
          ),
          _BarAction(
            key: const ValueKey('selection_rename'),
            icon: Icons.drive_file_rename_outline_rounded,
            label: 'إعادة تسمية',
            onTap: onRename,
            disabledHint: 'حدد عنصراً واحداً فقط لإعادة تسميته',
          ),
          _BarAction(
            key: const ValueKey('selection_download'),
            icon: Icons.download_rounded,
            label: 'تنزيل',
            onTap: onDownload,
            disabledHint: 'التنزيل غير متاح الآن',
          ),
        ],
      ),
    );
  }
}

class _BarAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final String? disabledHint;

  const _BarAction({
    super.key,
    required this.icon,
    required this.label,
    this.color = NexusColors.textSecondary,
    this.onTap,
    this.disabledHint,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final tint = enabled ? color : NexusColors.textSubtle.withOpacity(0.55);

    final content = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: tint),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: tint),
            ),
          ],
        ),
      ),
    );

    return Expanded(
      child: Semantics(
        button: true,
        enabled: enabled,
        label: label,
        child: Material(
          color: Colors.transparent,
          child: !enabled && disabledHint != null
              ? Tooltip(message: disabledHint!, child: content)
              : content,
        ),
      ),
    );
  }
}

/// "Done — undo" strip shown after a successful commit.
class RepoUndoBar extends StatelessWidget {
  final String summary;
  final VoidCallback onUndo;
  final VoidCallback onDismiss;

  const RepoUndoBar({
    super.key,
    required this.summary,
    required this.onUndo,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      padding: const EdgeInsetsDirectional.fromSTEB(14, 4, 4, 4),
      decoration: BoxDecoration(
        color: NexusColors.bgElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NexusColors.successSoft.withOpacity(0.35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_outline_rounded,
            size: 20,
            color: NexusColors.successSoft,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              summary,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: NexusColors.textPrimary,
              ),
            ),
          ),
          TextButton(
            key: const ValueKey('undo_button'),
            onPressed: onUndo,
            style: TextButton.styleFrom(
              foregroundColor: NexusColors.primarySoft,
            ),
            child: const Text(
              'تراجع',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            tooltip: 'إخفاء',
            visualDensity: VisualDensity.compact,
            onPressed: onDismiss,
            icon: const Icon(
              Icons.close_rounded,
              size: 18,
              color: NexusColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Dimmed overlay that blocks the screen while a commit / undo is running.
class RepoBusyOverlay extends StatelessWidget {
  final String label;

  const RepoBusyOverlay({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ModalBarrier(
          dismissible: false,
          color: Colors.black.withOpacity(0.55),
        ),
        Center(
          child: GlassPanel(
            strong: true,
            borderRadius: 18,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: NexusColors.primarySoft,
                  ),
                ),
                const SizedBox(width: 14),
                Flexible(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: NexusColors.textPrimary,
                    ),
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
