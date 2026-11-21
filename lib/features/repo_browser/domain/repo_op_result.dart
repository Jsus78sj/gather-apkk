import 'package:dio/dio.dart';
import '../../../core/network/github_exceptions.dart';

/// Why a repository write (preview / commit / undo) did not go through.
/// The UI uses it to decide what happens next (refresh, keep the dialog...).
enum RepoOpFailure {
  /// The branch moved on GitHub after the listing was loaded.
  branchChanged,

  /// Token / account has no write access.
  permission,

  /// Branch protection rejected the direct push.
  protectedBranch,
  rateLimit,
  network,

  /// Rejected locally before any write (bad path, nothing to do...).
  invalid,
  unknown,
}

/// Outcome of a controller write operation: either a [value] or a
/// [failure] with a ready-to-show Arabic [message].
class RepoOpResult<T> {
  final T? value;
  final RepoOpFailure? failure;
  final String? message;

  const RepoOpResult.success(this.value)
      : failure = null,
        message = null;

  const RepoOpResult.failed(RepoOpFailure this.failure, String this.message)
      : value = null;

  bool get isSuccess => failure == null;

  /// Maps any error thrown by the engine / API client to a failed result.
  static RepoOpResult<T> fromError<T>(Object error) {
    if (error is BranchChangedException) {
      return RepoOpResult.failed(RepoOpFailure.branchChanged, error.message);
    }
    if (error is ProtectedBranchException) {
      return RepoOpResult.failed(RepoOpFailure.protectedBranch, error.message);
    }
    if (error is InsufficientScopeException || error is InvalidTokenException) {
      return RepoOpResult.failed(
        RepoOpFailure.permission,
        (error as GitHubException).message,
      );
    }
    if (error is RateLimitException) {
      return RepoOpResult.failed(RepoOpFailure.rateLimit, error.message);
    }
    if (error is NetworkConnectionException) {
      return RepoOpResult.failed(RepoOpFailure.network, error.message);
    }
    if (error is InvalidRepoOperationException) {
      return RepoOpResult.failed(RepoOpFailure.invalid, error.message);
    }
    if (error is GitHubApiException) {
      // A 403 that reached us untranslated is still a permission problem.
      return RepoOpResult.failed(
        error.statusCode == 403
            ? RepoOpFailure.permission
            : RepoOpFailure.unknown,
        error.message,
      );
    }
    if (error is GitHubException) {
      return RepoOpResult.failed(RepoOpFailure.unknown, error.message);
    }
    if (error is DioException) {
      if (CancelToken.isCancel(error)) {
        return RepoOpResult.failed(
          RepoOpFailure.unknown,
          'أُلغيت العملية.',
        );
      }
      return RepoOpResult.failed(
        RepoOpFailure.network,
        'تعذر الاتصال بخوادم GitHub. تحقق من اتصال الإنترنت.',
      );
    }
    return RepoOpResult.failed(
      RepoOpFailure.unknown,
      'حدث خطأ غير متوقع أثناء تنفيذ العملية.',
    );
  }
}
