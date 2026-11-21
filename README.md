# GitHub Nexus — Repo Manager Pro (v1.1.0)

Production-ready Flutter Android APK application converted and upgraded from **GitHub Nexus** across 5 engineering phases (v1.0.0), then extended with a full repository file manager (phases 6–10; all done in v1.1.0).

## Architecture & Completed Phases

### Phase 1 — Core Architecture & Secure Auth
- Offline Dark Glassmorphism UI (`NexusColors`, `NexusTheme`, `GlassPanel`, `NexusAmbientBackground`, `NexusGradientButton`, `showNexusToast`).
- `GitHubApiClient` (Dio) with `2022-11-28` headers, exponential backoff retry (5xx / 429 / timeouts), and live `X-RateLimit-*` monitoring.
- Multi-account encrypted PAT storage via **Android Keystore (`EncryptedSharedPreferences`)** supporting both Classic (`ghp_`) and Fine-Grained (`github_pat_`) tokens.

### Phase 2 — Repositories & Branches Manager
- Paginated repository fetching with Pull-to-Refresh, instant search, visibility filters (`All` / `Public` / `Private`), and sorting (`Updated` / `Name` / `Stars`).
- Create Repository modal, Branch Switcher & Creator (with Git ref validation), and automatic Empty Repository detection with 1-tap `README.md` initialization.

### Phase 3 — Streaming ZIP Explorer & Pre-Deploy Filtering
- Zero-decompression `StreamingZipInspector` (ZIP64 + Zip-Slip guard) executed inside `Isolate.run` for smooth inspection of archives up to 100 MB.
- System File Picker + native Android Share Sheet (`ACTION_SEND` / `ACTION_VIEW`) with 64 KB buffered copy.
- Hierarchical Tree View with tri-state selection, automatic single-root folder stripping, preset & custom exclusion rules, and 100 MB limit auto-remediation.

### Phase 4 — Atomic Deploy Engine & Background Foreground Service
- **Git Data API Single-Commit Engine (`AtomicDeployEngine`)** with 6x parallel streaming blob uploads.
- **Full Sync (Mirror)** with live Added / Updated / Deleted confirmation modal and atomic tree replacement (zero individual `DELETE` requests).
- **Partial Update (Merge)** preserving untouched remote files via `base_tree`.
- Automatic empty-repo bootstrap fallback, selective **Retry Failed Files Only** reusing uploaded Blob SHAs, and native Android `DeployForegroundService` (`dataSync` + `WakeLock` + Cancel notification button) with Live Console Log.

### Phase 5 — QA Integration Tests, Release Optimization & CI/CD
- End-to-end integration tests (`test/integration/end_to_end_deploy_flow_test.dart`) & widget smoke tests (`test/widget/app_smoke_test.dart`).
- Adaptive Android Launcher Icons (vector + legacy densities + round icons) and Android 12+ native Splash Screen (`values-v31/styles.xml`).
- R8 code shrinking, resource shrinking, and tailored `proguard-rules.pro` protecting Keystore/Tink/ForegroundService.
- Signing config (`android/key.properties.example`), helper scripts (`scripts/`), and GitHub Actions workflow (`.github/workflows/build_release_apk.yml`) producing split-per-ABI + universal release APKs with SHA-256 checksums.

### Phase 6 — Repository Data Layer & Atomic File Engine (v1.1.0)
- `GitHubApiClient`: `fetchTreeShallow`, `fetchFileBlob`, `fetchCommits`; `GitTreeItemInput.delete` (tree entry with `sha: null`).
- `RepoContentService`: folder-by-folder browsing with per-tree cache; works when the recursive tree is `truncated`.
- `RepoFilesEngine`: applies `CreateFileOp` / `UpdateFileOp` / `DeleteOp` (file or folder) / `RenameOp` (file or folder) as **one atomic commit** (`previewChanges`, `applyChanges`, `undoCommit`), with path validation, mode preservation, branch-moved detection (`BranchChangedException`) and non-forced ref updates.
- Tests: `test/features/repo_browser/`.

### Phase 7 — Repository File Browser (read-only)
- **Entry point:** the "تصفّح ملفات المستودع" button in the repositories section opens `RepoBrowserScreen` for the selected repository + branch (`lib/features/repo_browser/presentation/`).
- **Browsing:** breadcrumb path bar, folders-first listing with sizes, executable / symlink / submodule badges, pull-to-refresh, branch switcher (keeps the deploy target in sync), system-back goes up one folder before leaving the screen.
- **Race-safe navigation:** every navigation is sequenced and cancellable, so a slow response can never overwrite a newer folder; a folder deleted remotely falls back to its nearest existing parent on refresh.
- **File viewer:** syntax-highlighted code (dependency-free tokenizer for 20+ languages, highlighting runs in an isolate above 60 KB), rendered Markdown (headings, lists, task boxes, tables, code fences, links), pinch-zoom images, and an info card for binary / oversized files (never downloaded when the name already says "binary"). Always left-to-right for code, with line numbers, soft-wrap toggle, copy, and file info (SHA, mode, BOM, line endings).
- **Local file-name search:** one recursive-tree request builds an in-memory index; matching is case-insensitive, multi-word, ranks file-name prefixes first, and warns when GitHub truncated the tree of a huge repository.
- **Tests:** `test/features/repo_browser/` — file classification, Markdown parser, syntax highlighter, search index, browser controller (navigation races, refresh fallback, indexing errors) and widget tests for the screen, breadcrumb, entry tile, code and Markdown views.

### Phase 8A — Multi-selection, delete & undo
- **Selection mode:** a long press on a row starts it; later taps toggle rows. Selecting a folder selects everything inside it. Header shows the counter, "select all" and cancel; system back closes the selection before leaving the folder. Submodules cannot be selected.
- **Bottom action bar:** delete, move, rename and download (see 8B below).
- **Confirmation dialog:** `previewChanges` summary (selected items, files that will really disappear, a few examples), an explicit warning when a folder is included, and an editable commit message with a default (`Nexus: delete …`).
- **Execution:** `RepoFilesEngine.applyChanges` with `expectedHeadSha` — ONE commit for any number of files and folders. Failures map to Arabic messages: branch moved (`BranchChangedException`, listing reloads), missing write permission, protected branch, rate limit, network.
- **Undo bar:** after success `undoCommit` reverts the commit with one tap; the bar disappears after 20 s, when dismissed, or when the branch head moves.
- **Tests:** `repo_delete_flow_test.dart` (selection state, preview, delete + undo, every failure path) and `repo_selection_ui_test.dart` (widgets: selection mode, action bar, confirmation dialog, full delete → undo flow on the screen).

### Phase 8B — Move, rename & download
- **Move:** bottom-sheet destination picker (browse folders, optional new sub-folder, root). A folder can never go inside itself or stay in the same folder. `previewChanges` → confirmation dialog (items, affected files, editable commit message `Nexus: move …`) → `RepoFilesEngine.applyChanges` with `RenameOp`s in **one commit**. Nothing is re-uploaded: the new path points at the existing blob SHA and the old path is removed.
- **Rename:** enabled for exactly one selected item. A file asks for the new name and the commit message in one dialog; a folder goes through the confirmation dialog because every file inside changes path. Case-only renames, Arabic and spaced names are supported; name collisions are refused before any write.
- **Download:** a single file is saved as is; a folder or several items become one ZIP (paths relative to the folder being browsed, UTF-8 names). Blobs are read 4 at a time, the archive is zipped in an isolate above 2 MB, and selections above 50 MB are refused. Read-only: no commit is created, and the selection is kept if the save dialog is cancelled.
- **Undo:** the undo bar now covers delete, move and rename, with a message per kind (`RepoUndoKind`).
- **Tests:** `repo_path_actions_test.dart` (controller: single commit, blob reuse, collisions, invalid names, failures, undo, download payloads) and `repo_path_actions_ui_test.dart` (widgets: rename, folder rename, move picker, download with a fake saver).

### Phase 9 — Text editor (edit & save in one commit)
- **Entry point:** an edit button (`viewer_edit`) in the file viewer for text / Markdown files. Guards (`RepoEditGuard`): write access required, no symlinks, no binary files, 1 MB limit; the reason is shown as a toast.
- **Editor** (`repo_file_editor_screen.dart`): always LTR, line numbers, undo / redo (`EditorHistory`), find & replace (plain text or Regex), unsaved-changes guard on back.
- **Save flow:** encode (CRLF + BOM preserved) → `RepoBrowserController.checkEditConflict` → line diff dialog with editable commit message → `saveFileEdit` = `RepoFilesEngine.applyChanges([UpdateFileOp])`, ONE commit, ref updated without `force`, executable bit (`100755`) preserved.
- **Conflict detection:** the branch head at open time is compared with the current head; a changed head warns, and a changed / deleted file offers copy edits, reload latest, or (only if the file is untouched or after explicit approval) continue on the latest head.
- **Undo:** the browser's undo bar now also reverts an edit (`RepoUndoKind.edit`). `RepoCommitResult.uploadedBlobShas` gives the new blob SHA, so the viewer shows the saved version without extra requests.
- **Tests:** `repo_file_edit_flow_test.dart` (conflict check, save, mode, undo, stale head, protected branch, permissions, size limit, symlink) `repo_file_editor_ui_test.dart` (widgets: open editor, read-only repo, binary file, edit → diff → commit → undo, cancel, discard guard, three conflict cases) plus the existing `line_diff`, `editor_history_and_search` and `repo_text_codec` tests.

### Phase 10 — Create / upload / history / PR / search / favorites (v1.1.0)
- **Create file or folder:** the `+` menu opens `CreateEntryDialog`; a file carries optional initial content, and an empty folder is materialized by a `.gitkeep` inside it. Everything lands in ONE atomic commit (`Nexus: create …`), paths may span nested folders, and duplicates / invalid paths are refused before any request.
- **Upload from the phone:** `pickAndConfirmLocalFilesUpload` (file_picker) reads files with their bytes and shows a review dialog with sizes, per-file collision highlighting and an explicit overwrite switch. Without overwrite a colliding name is refused; with it the upload becomes an update that preserves the remote file mode. All files of one upload are committed together.
- **File history & restore:** the viewer's overflow menu opens `showFileHistorySheet` — the commit list that touched this file (`fetchCommits` with a `path` filter), and a "استعادة" action on any older version. Restore reads the file exactly as it was (`fetchCommitTreeSha` + a snapshot service), then commits it as a NEW commit on the branch head (history is never rewritten), preserving the historic file mode; an identical version or a missing file is refused. The undo bar covers the restore too.
- **Protected branch → new branch + pull request:** when a direct push is rejected by branch protection (`RepoOpFailure.protectedBranch`), the rejected ops are kept (`takeRejectedWriteOps`) and `ProtectedBranchPrDialog` appears automatically in the browser screen AND in the editor save flow. It creates a branch from the current one (`nexus/patch-YYYYMMDD-HHMM` default), applies the SAME ops on it atomically, opens the pull request back into the protected branch (`createPullRequest`), shows the PR number + URL, and deletes the created branch again if anything fails — nothing is half-done.
- **Content search:** the search screen gained a mode toggle — "الأسماء" (the local index) and "المحتوى" (GitHub Search API with text-match snippets). Content search runs on submit only, is throttled locally by `SearchRateLimiter` (8/min — refused requests are counted by GitHub too, so the wait is enforced before sending), warns about `incomplete_results`, and hits open the file in the viewer.
- **Favorites & recents:** `RepoBookmarksController` persists favorites (files and folders) and the last 30 opened files per repo + branch in encrypted storage (`RepoBookmarksStorage`). The viewer records recents on open and toggles favorites with a star; the browser menu toggles the current folder; the bookmarks sheet lists both tabs and navigates on tap (folders open in place, files are resolved against the loaded snapshot first and a missing file says so).
- **Toasts are non-blocking:** `showNexusToast` was reworked from a bottom floating SnackBar (which sat above the undo bar and swallowed its taps for 4 s) into a top overlay banner wrapped in `IgnorePointer`, so a success toast can never block the undo underneath it.
- **Bug fixes found while wiring:** `fetchCommits` decoded every response as `List<dynamic>`, so the 409 object body of an empty repository crashed before the empty-history check could run — it now checks the status first (`repo_api_methods_test.dart` covers it).
- **Tests:** `repo_phase10_ops_test.dart` (23 tests: create file / folder / duplicates / invalid paths, upload with and without overwrite, history fetch, restore incl. mode preservation and identical/missing refusals, `resolveFileRef`, protected-branch fallback success + cleanup + local refusals, content search incl. quota and failure paths, rate limiter) and `repo_phase10_ui_test.dart` (8 widget tests: create via the menu, folder favorite toggle, recents recording + sheet navigation, viewer star, content-search submit-only flow, the full protected-branch → PR dialog flow, opening a bookmark folder).

## Quick Commands
```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release --split-per-abi
```

See `RELEASE_CHECKLIST.md` for keystore generation and GitHub Actions Secrets setup.
