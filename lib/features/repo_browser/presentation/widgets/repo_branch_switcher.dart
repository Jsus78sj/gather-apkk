import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/nexus_colors.dart';
import '../../../../core/widgets/glass_panel.dart';
import '../../../repos/presentation/repos_controller.dart';

/// Compact `⑂ main ▾` pill that opens the branch list.
///
/// Switching the branch updates [reposControllerProvider], which rebuilds the
/// browser at the root of the chosen branch (and keeps the deploy target in
/// sync with what the user is looking at).
class RepoBranchButton extends ConsumerWidget {
  const RepoBranchButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branch = ref.watch(
      reposControllerProvider.select((s) => s.selectedBranch),
    );
    final branchCount = ref.watch(
      reposControllerProvider.select((s) => s.branches.length),
    );
    final canSwitch = branchCount > 1;

    return Material(
      color: NexusColors.bgElevated.withOpacity(0.6),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: canSwitch ? () => showRepoBranchSheet(context) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: NexusColors.borderSubtle),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.call_split_rounded,
                size: 13,
                color: NexusColors.primarySoft,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  branch ?? '—',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                    color: NexusColors.textSecondary,
                  ),
                ),
              ),
              if (canSwitch)
                const Icon(
                  Icons.arrow_drop_down_rounded,
                  size: 18,
                  color: NexusColors.textMuted,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showRepoBranchSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _BranchSheet(),
  );
}

class _BranchSheet extends ConsumerWidget {
  const _BranchSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branches = ref.watch(reposControllerProvider.select((s) => s.branches));
    final selected = ref.watch(
      reposControllerProvider.select((s) => s.selectedBranch),
    );
    final maxHeight = MediaQuery.sizeOf(context).height * 0.6;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: GlassPanel(
          strong: true,
          borderRadius: 22,
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(10, 0, 10, 10),
                  child: Text(
                    'تبديل الفرع',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: NexusColors.textPrimary,
                    ),
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: branches.length,
                    itemBuilder: (context, index) {
                      final branch = branches[index];
                      final isSelected = branch.name == selected;
                      return ListTile(
                        dense: true,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        selected: isSelected,
                        selectedTileColor: NexusColors.primary.withOpacity(0.12),
                        leading: Icon(
                          isSelected
                              ? Icons.check_circle_rounded
                              : Icons.call_split_rounded,
                          size: 19,
                          color: isSelected
                              ? NexusColors.primarySoft
                              : NexusColors.textMuted,
                        ),
                        title: Text(
                          branch.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: TextDirection.ltr,
                          textAlign: TextAlign.start,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13.5,
                            color: NexusColors.textPrimary,
                          ),
                        ),
                        subtitle: Text(
                          branch.shortSha,
                          textDirection: TextDirection.ltr,
                          textAlign: TextAlign.start,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: NexusColors.textSubtle,
                          ),
                        ),
                        trailing: branch.isProtected
                            ? const Icon(
                                Icons.shield_outlined,
                                size: 16,
                                color: NexusColors.warningSoft,
                              )
                            : null,
                        onTap: () {
                          final controller =
                              ref.read(reposControllerProvider.notifier);
                          Navigator.of(context).pop();
                          if (!isSelected) controller.selectBranch(branch.name);
                        },
                      );
                    },
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
