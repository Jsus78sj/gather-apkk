import 'package:flutter/material.dart';
import '../../../../core/theme/nexus_colors.dart';
import '../../domain/remote_tree_entry.dart';
import '../../domain/repo_file_kind.dart';

class RepoEntryVisual {
  final IconData icon;
  final Color color;

  const RepoEntryVisual(this.icon, this.color);
}

/// Icon + accent color of a file / folder row.
abstract final class RepoEntryVisuals {
  static const Set<String> _archives = {
    'zip', 'gz', 'tgz', 'tar', '7z', 'rar', 'bz2', 'xz', 'jar', 'war', 'apk',
    'aab', 'ipa',
  };
  static const Set<String> _audio = {'mp3', 'wav', 'ogg', 'flac', 'm4a'};
  static const Set<String> _video = {'mp4', 'mov', 'avi', 'mkv', 'webm'};
  static const Set<String> _config = {
    'json', 'yaml', 'yml', 'toml', 'ini', 'cfg', 'conf', 'properties', 'env',
    'xml', 'plist', 'arb', 'lock',
  };
  static const Set<String> _scripts = {'sh', 'bash', 'zsh', 'fish', 'bat', 'cmd'};

  static RepoEntryVisual forEntry(RemoteTreeEntry entry) {
    if (entry.isFolder) {
      return const RepoEntryVisual(Icons.folder_rounded, NexusColors.warningSoft);
    }
    if (entry.isSubmodule) {
      return const RepoEntryVisual(
        Icons.account_tree_outlined,
        NexusColors.violet,
      );
    }
    if (entry.isSymlink) {
      return const RepoEntryVisual(Icons.link_rounded, NexusColors.textMuted);
    }
    return forFileName(entry.name);
  }

  static RepoEntryVisual forFileName(String name) {
    final ext = RepoFileKinds.extensionOf(name);

    if (_archives.contains(ext)) {
      return const RepoEntryVisual(
        Icons.folder_zip_outlined,
        NexusColors.roseSoft,
      );
    }
    if (ext == 'pdf') {
      return const RepoEntryVisual(
        Icons.picture_as_pdf_outlined,
        NexusColors.roseSoft,
      );
    }
    if (_audio.contains(ext)) {
      return const RepoEntryVisual(
        Icons.audio_file_outlined,
        NexusColors.violet,
      );
    }
    if (_video.contains(ext)) {
      return const RepoEntryVisual(
        Icons.video_file_outlined,
        NexusColors.violet,
      );
    }
    if (_scripts.contains(ext)) {
      return const RepoEntryVisual(
        Icons.terminal_rounded,
        NexusColors.successSoft,
      );
    }
    if (_config.contains(ext)) {
      return const RepoEntryVisual(
        Icons.data_object_rounded,
        NexusColors.warningSoft,
      );
    }

    return switch (RepoFileKinds.byName(name)) {
      RepoFileKind.image => const RepoEntryVisual(
          Icons.image_outlined,
          NexusColors.successSoft,
        ),
      RepoFileKind.markdown => const RepoEntryVisual(
          Icons.article_outlined,
          NexusColors.primarySoft,
        ),
      RepoFileKind.binary => const RepoEntryVisual(
          Icons.insert_drive_file_outlined,
          NexusColors.textSubtle,
        ),
      RepoFileKind.text => RepoFileKinds.languageOf(name) != null
          ? const RepoEntryVisual(Icons.code_rounded, NexusColors.indigo)
          : const RepoEntryVisual(
              Icons.description_outlined,
              NexusColors.textMuted,
            ),
      null => const RepoEntryVisual(
          Icons.insert_drive_file_outlined,
          NexusColors.textMuted,
        ),
    };
  }
}
