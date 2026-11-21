import 'package:flutter/material.dart';
import '../../../../core/theme/nexus_colors.dart';

/// شريط البحث والاستبدال المدمج داخل محرر النصوص.
class EditorFindReplaceBar extends StatelessWidget {
  final TextEditingController findController;
  final TextEditingController replaceController;
  final bool showReplace;
  final bool caseSensitive;
  final bool useRegex;
  final String? regexError;
  final int matchCount;
  final int activeMatchIndex; // 0-based، أو -1 إذا لا توجد نتائج
  final VoidCallback onToggleReplace;
  final VoidCallback onToggleCaseSensitive;
  final VoidCallback onToggleRegex;
  final VoidCallback onFindPrevious;
  final VoidCallback onFindNext;
  final VoidCallback onReplaceCurrent;
  final VoidCallback onReplaceAll;
  final VoidCallback onClose;
  final ValueChanged<String> onQueryChanged;

  const EditorFindReplaceBar({
    super.key,
    required this.findController,
    required this.replaceController,
    required this.showReplace,
    required this.caseSensitive,
    required this.useRegex,
    required this.regexError,
    required this.matchCount,
    required this.activeMatchIndex,
    required this.onToggleReplace,
    required this.onToggleCaseSensitive,
    required this.onToggleRegex,
    required this.onFindPrevious,
    required this.onFindNext,
    required this.onReplaceCurrent,
    required this.onReplaceAll,
    required this.onClose,
    required this.onQueryChanged,
  });

  @override
  Widget build(BuildContext context) {
    final counterLabel = findController.text.isEmpty
        ? ''
        : (matchCount == 0 ? '0' : '${activeMatchIndex + 1}/$matchCount');

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      decoration: BoxDecoration(
        color: NexusColors.bgSurface.withOpacity(0.95),
        border: const Border(
          bottom: BorderSide(color: NexusColors.borderAccent),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                key: const ValueKey('editor_toggle_replace'),
                tooltip: showReplace ? 'إخفاء الاستبدال' : 'إظهار الاستبدال',
                visualDensity: VisualDensity.compact,
                onPressed: onToggleReplace,
                icon: Icon(
                  showReplace
                      ? Icons.keyboard_arrow_down_rounded
                      : Icons.keyboard_arrow_left_rounded,
                  size: 20,
                  color: NexusColors.textMuted,
                ),
              ),
              Expanded(
                child: TextField(
                  key: const ValueKey('editor_find_input'),
                  controller: findController,
                  textDirection: TextDirection.ltr,
                  onChanged: onQueryChanged,
                  onSubmitted: (_) => onFindNext(),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12.5,
                    color: NexusColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'بحث...',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    suffixText: counterLabel,
                    suffixStyle: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: NexusColors.primarySoft,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              _MiniToggle(
                key: const ValueKey('editor_toggle_case'),
                label: 'Aa',
                tooltip: 'مطابقة حالة الأحرف',
                active: caseSensitive,
                onTap: onToggleCaseSensitive,
              ),
              const SizedBox(width: 4),
              _MiniToggle(
                key: const ValueKey('editor_toggle_regex'),
                label: '.*',
                tooltip: 'تعبير نمطي (Regex)',
                active: useRegex,
                onTap: onToggleRegex,
              ),
              IconButton(
                key: const ValueKey('editor_find_prev'),
                tooltip: 'السابق',
                visualDensity: VisualDensity.compact,
                onPressed: matchCount > 0 ? onFindPrevious : null,
                icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 20),
              ),
              IconButton(
                key: const ValueKey('editor_find_next'),
                tooltip: 'التالي',
                visualDensity: VisualDensity.compact,
                onPressed: matchCount > 0 ? onFindNext : null,
                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
              ),
              IconButton(
                key: const ValueKey('editor_find_close'),
                tooltip: 'إغلاق البحث',
                visualDensity: VisualDensity.compact,
                onPressed: onClose,
                icon: const Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: NexusColors.textMuted,
                ),
              ),
            ],
          ),
          if (regexError != null) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                regexError!,
                style: const TextStyle(
                  fontSize: 11,
                  color: NexusColors.roseSoft,
                ),
              ),
            ),
          ],
          if (showReplace) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const SizedBox(width: 40),
                Expanded(
                  child: TextField(
                    key: const ValueKey('editor_replace_input'),
                    controller: replaceController,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12.5,
                      color: NexusColors.textPrimary,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'استبدال بـ...',
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                OutlinedButton(
                  key: const ValueKey('editor_replace_one'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: NexusColors.primarySoft,
                    side: BorderSide(
                      color: NexusColors.primary.withOpacity(0.4),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: matchCount > 0 ? onReplaceCurrent : null,
                  child: const Text('استبدال', style: TextStyle(fontSize: 11.5)),
                ),
                const SizedBox(width: 4),
                OutlinedButton(
                  key: const ValueKey('editor_replace_all'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: NexusColors.warningSoft,
                    side: BorderSide(
                      color: NexusColors.warning.withOpacity(0.4),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: matchCount > 0 ? onReplaceAll : null,
                  child: const Text('الكل', style: TextStyle(fontSize: 11.5)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniToggle extends StatelessWidget {
  final String label;
  final String tooltip;
  final bool active;
  final VoidCallback onTap;

  const _MiniToggle({
    super.key,
    required this.label,
    required this.tooltip,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
          decoration: BoxDecoration(
            color: active
                ? NexusColors.primary.withOpacity(0.22)
                : NexusColors.bgElevated.withOpacity(0.5),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active
                  ? NexusColors.primary
                  : NexusColors.borderSubtle,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: active ? NexusColors.primarySoft : NexusColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}
