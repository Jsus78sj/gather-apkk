import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/nexus_colors.dart';
import '../../../core/widgets/glass_panel.dart';
import '../domain/arabic_count.dart';
import '../domain/remote_tree_entry.dart';
import '../domain/repo_path_validator.dart';

typedef FolderLister = Future<List<RemoteTreeEntry>> Function(
  String folderPath, {
  CancelToken? cancelToken,
});

/// يفتح منتقي المجلد الهدف لعملية النقل.
/// يُرجع المسار النسبي المختار (`''` = الجذر)، أو `null` عند الإلغاء.
Future<String?> showMoveDestinationSheet(
  BuildContext context, {
  required String repoName,
  required String currentFolderPath,
  required Set<String> selectedPaths,
  required FolderLister listFolders,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _MoveDestinationSheet(
      repoName: repoName,
      currentFolderPath: currentFolderPath,
      selectedPaths: selectedPaths,
      listFolders: listFolders,
    ),
  );
}

class _MoveDestinationSheet extends StatefulWidget {
  final String repoName;
  final String currentFolderPath;
  final Set<String> selectedPaths;
  final FolderLister listFolders;

  const _MoveDestinationSheet({
    required this.repoName,
    required this.currentFolderPath,
    required this.selectedPaths,
    required this.listFolders,
  });

  @override
  State<_MoveDestinationSheet> createState() => _MoveDestinationSheetState();
}

class _MoveDestinationSheetState extends State<_MoveDestinationSheet> {
  final TextEditingController _newSubfolderController = TextEditingController();
  late String _browsePath;
  List<RemoteTreeEntry> _folders = const [];
  bool _loading = true;
  String? _error;
  CancelToken? _cancel;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _browsePath = '';
    _loadFolder('');
  }

  @override
  void dispose() {
    _cancel?.cancel();
    _newSubfolderController.dispose();
    super.dispose();
  }

  Future<void> _loadFolder(String path) async {
    _cancel?.cancel();
    final cancel = _cancel = CancelToken();
    final seq = ++_seq;
    setState(() {
      _browsePath = path;
      _loading = true;
      _error = null;
    });

    try {
      final folders = await widget.listFolders(path, cancelToken: cancel);
      if (!mounted || seq != _seq) return;
      setState(() {
        _folders = folders;
        _loading = false;
      });
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) return;
      if (!mounted || seq != _seq) return;
      setState(() {
        _loading = false;
        _error = 'تعذر تحميل المجلدات.';
      });
    } catch (_) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _loading = false;
        _error = 'تعذر تحميل المجلدات.';
      });
    }
  }

  String _childPath(String name) =>
      _browsePath.isEmpty ? name : '$_browsePath/$name';

  bool _isBlockedDestination(String folderPath) {
    for (final selected in widget.selectedPaths) {
      if (folderPath == selected ||
          RepoPathValidator.isInside(selected, folderPath)) {
        return true;
      }
    }
    return false;
  }

  String get _resolvedDestination {
    var extra = _newSubfolderController.text.trim().replaceAll('\\', '/');
    while (extra.startsWith('/')) {
      extra = extra.substring(1);
    }
    while (extra.endsWith('/')) {
      extra = extra.substring(0, extra.length - 1);
    }
    if (extra.isEmpty) return _browsePath;
    return _browsePath.isEmpty ? extra : '$_browsePath/$extra';
  }

  String? get _destinationError {
    final dest = _resolvedDestination;
    if (dest.isNotEmpty) {
      final err = RepoPathValidator.validate(dest);
      if (err != null) return err;
    }
    if (_isBlockedDestination(dest)) {
      return 'لا يمكن نقل مجلد إلى داخل نفسه.';
    }
    if (dest == widget.currentFolderPath) {
      return 'اختر مجلداً مختلفاً عن المجلد الحالي.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final segments = _browsePath.isEmpty ? const <String>[] : _browsePath.split('/');
    final dest = _resolvedDestination;
    final destError = _destinationError;

    return Padding(
      padding: EdgeInsets.fromLTRB(12, 24, 12, 12 + bottomInset),
      child: GlassPanel(
        strong: true,
        borderRadius: 24,
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.drive_file_move_outline,
                  color: NexusColors.primarySoft,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'نقل ${arabicItems(widget.selectedPaths.length)} إلى...',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: NexusColors.textPrimary,
                        ),
                      ),
                      Text(
                        dest.isEmpty ? 'الجذر (/)' : '/$dest',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontFamily: 'monospace',
                          color: NexusColors.primarySoft,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(
                    Icons.close_rounded,
                    color: NexusColors.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Breadcrumb داخل المنتقي
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Row(
                  children: [
                    _CrumbChip(
                      label: widget.repoName,
                      active: segments.isEmpty,
                      onTap: () => _loadFolder(''),
                    ),
                    for (var i = 0; i < segments.length; i++) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          '/',
                          style: TextStyle(color: NexusColors.textSubtle),
                        ),
                      ),
                      _CrumbChip(
                        label: segments[i],
                        active: i == segments.length - 1,
                        onTap: () => _loadFolder(
                          segments.sublist(0, i + 1).join('/'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),

            // قائمة المجلدات الفرعية
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 140, maxHeight: 240),
              child: Container(
                decoration: BoxDecoration(
                  color: NexusColors.bgDeep.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: NexusColors.borderSubtle),
                ),
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: NexusColors.primarySoft,
                        ),
                      )
                    : _error != null
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _error!,
                                  style: const TextStyle(
                                    color: NexusColors.roseSoft,
                                    fontSize: 12.5,
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => _loadFolder(_browsePath),
                                  child: const Text('إعادة المحاولة'),
                                ),
                              ],
                            ),
                          )
                        : _folders.isEmpty
                            ? const Center(
                                child: Text(
                                  'لا توجد مجلدات فرعية هنا',
                                  style: TextStyle(
                                    color: NexusColors.textMuted,
                                    fontSize: 12.5,
                                  ),
                                ),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                itemCount: _folders.length,
                                separatorBuilder: (_, __) => const Divider(
                                  height: 1,
                                  color: NexusColors.borderSubtle,
                                ),
                                itemBuilder: (_, idx) {
                                  final folder = _folders[idx];
                                  final full = _childPath(folder.name);
                                  final blocked = _isBlockedDestination(full);
                                  return Material(
                                    type: MaterialType.transparency,
                                    child: ListTile(
                                    dense: true,
                                    enabled: !blocked,
                                    leading: Icon(
                                      Icons.folder_rounded,
                                      size: 20,
                                      color: blocked
                                          ? NexusColors.textSubtle
                                          : NexusColors.warningSoft,
                                    ),
                                    title: Text(
                                      folder.name,
                                      textDirection: TextDirection.ltr,
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 13,
                                        color: blocked
                                            ? NexusColors.textSubtle
                                            : NexusColors.textPrimary,
                                      ),
                                    ),
                                    subtitle: blocked
                                        ? const Text(
                                            'محدد للنقل',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: NexusColors.textSubtle,
                                            ),
                                          )
                                        : null,
                                    trailing: blocked
                                        ? null
                                        : const Icon(
                                            Icons.chevron_right_rounded,
                                            size: 18,
                                            color: NexusColors.textMuted,
                                          ),
                                    onTap: blocked
                                        ? null
                                        : () {
                                            _newSubfolderController.clear();
                                            _loadFolder(full);
                                          },
                                    ),
                                  );
                                },
                              ),
              ),
            ),
            const SizedBox(height: 12),

            // حقل اختياري لمجلد جديد داخل المسار المفتوح
            TextField(
              key: const ValueKey('move_new_subfolder'),
              controller: _newSubfolderController,
              textDirection: TextDirection.ltr,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12.5,
                color: NexusColors.textPrimary,
              ),
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'مجلد فرعي جديد (اختياري، مثل: archive/old)',
                prefixIcon: Icon(
                  Icons.create_new_folder_outlined,
                  size: 18,
                  color: NexusColors.textSubtle,
                ),
              ),
            ),

            if (destError != null) ...[
              const SizedBox(height: 8),
              Text(
                destError,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: NexusColors.warningSoft,
                ),
              ),
            ],
            const SizedBox(height: 14),

            NexusGradientButton(
              key: const ValueKey('move_select_destination'),
              height: 48,
              borderRadius: 13,
              onPressed: destError == null
                  ? () => Navigator.of(context).pop(dest)
                  : null,
              child: Text(
                dest.isEmpty ? 'نقل إلى الجذر (/)' : 'نقل إلى هذا المسار',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CrumbChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _CrumbChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: active ? null : onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: active
              ? NexusColors.primary.withOpacity(0.18)
              : NexusColors.bgElevated.withOpacity(0.5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active
                ? NexusColors.primary.withOpacity(0.45)
                : NexusColors.borderSubtle,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 11.5,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active ? NexusColors.primarySoft : NexusColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
