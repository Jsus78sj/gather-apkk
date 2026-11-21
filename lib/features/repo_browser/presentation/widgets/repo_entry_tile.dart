import 'package:flutter/material.dart';
import '../../../../core/theme/nexus_colors.dart';
import '../../../../core/utils/format_bytes.dart';
import '../../domain/remote_tree_entry.dart';
import '../../domain/repo_search_index.dart';
import 'repo_entry_visual.dart';

/// Rounded square holding the icon of a file / folder row.
class _EntryIcon extends StatelessWidget {
  final RepoEntryVisual visual;

  const _EntryIcon({required this.visual});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: visual.color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: visual.color.withOpacity(0.22)),
      ),
      child: Icon(visual.icon, size: 20, color: visual.color),
    );
  }
}

/// One row of the folder listing.
class RepoEntryTile extends StatelessWidget {
  final RemoteTreeEntry entry;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// Multi-selection mode: the trailing chevron becomes a check circle.
  final bool selectionMode;
  final bool selected;

  const RepoEntryTile({
    super.key,
    required this.entry,
    required this.onTap,
    this.onLongPress,
    this.selectionMode = false,
    this.selected = false,
  });

  /// Second line under the name (`null` for plain folders).
  static String? subtitleFor(RemoteTreeEntry entry) {
    if (entry.isFolder) return null;
    if (entry.isSubmodule) return 'Submodule';
    if (entry.isSymlink) return 'رابط رمزي';
    final size = formatBytes(entry.size);
    return entry.isExecutable ? '$size • قابل للتنفيذ' : size;
  }

  @override
  Widget build(BuildContext context) {
    final visual = RepoEntryVisuals.forEntry(entry);
    final subtitle = subtitleFor(entry);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: ColoredBox(
          color: selected
              ? NexusColors.primary.withOpacity(0.12)
              : Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                _EntryIcon(visual: visual),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: NexusColors.textPrimary,
                        ),
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: NexusColors.textSubtle,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (selectionMode)
                  Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 22,
                    color: selected
                        ? NexusColors.primarySoft
                        : NexusColors.textSubtle,
                  )
                else if (entry.isFolder)
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: NexusColors.textSubtle,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One row of the file-name search results (shows the containing folder).
class RepoSearchHitTile extends StatelessWidget {
  final RepoSearchHit hit;
  final VoidCallback onTap;

  const RepoSearchHitTile({super.key, required this.hit, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final visual = hit.isFolder
        ? const RepoEntryVisual(Icons.folder_rounded, NexusColors.warningSoft)
        : RepoEntryVisuals.forFileName(hit.name);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: [
              _EntryIcon(visual: visual),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hit.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: NexusColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          hit.parentPath.isEmpty ? '/' : hit.parentPath,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: NexusColors.textSubtle,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (!hit.isFolder) ...[
                const SizedBox(width: 8),
                Text(
                  formatBytes(hit.size),
                  style: const TextStyle(
                    fontSize: 11,
                    color: NexusColors.textSubtle,
                  ),
                ),
              ] else
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: NexusColors.textSubtle,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
