/// Typed exception hierarchy for GitHub REST / Git Data API failures.
sealed class GitHubException implements Exception {
  final String message;
  final int? statusCode;

  const GitHubException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

final class InvalidTokenException extends GitHubException {
  const InvalidTokenException([
    super.message = 'التوكن غير صالح أو منتهي الصلاحية. تحقق من الـ PAT وحاول مجدداً.',
  ]) : super(statusCode: 401);
}

final class InsufficientScopeException extends GitHubException {
  final List<String> grantedScopes;

  const InsufficientScopeException({
    required this.grantedScopes,
    String message = 'التوكن يفتقر إلى صلاحية (repo) المطلوبة لقراءة المستودعات والنشر.',
  }) : super(message, statusCode: 403);
}

final class RateLimitException extends GitHubException {
  final DateTime? resetAt;

  const RateLimitException({
    this.resetAt,
    String message = 'تم تجاوز حد طلبات GitHub API مؤقتاً. انتظر قليلاً ثم أعد المحاولة.',
  }) : super(message, statusCode: 403);
}

final class NetworkConnectionException extends GitHubException {
  const NetworkConnectionException([
    super.message = 'تعذر الاتصال بخوادم GitHub. تحقق من اتصال الإنترنت.',
  ]);
}

final class GitHubApiException extends GitHubException {
  const GitHubApiException(super.message, {super.statusCode});
}

/// Thrown when the remote branch moved after the user started editing /
/// staging changes (or when a ref update is rejected as non fast-forward).
final class BranchChangedException extends GitHubException {
  const BranchChangedException([
    super.message =
        'تغيّر الفرع على GitHub بعد بدء العملية. أعد تحميل الملفات ثم حاول مجدداً.',
  ]) : super(statusCode: 409);
}

/// Thrown for invalid file operations detected locally, before any write:
/// bad paths, name collisions, missing sources, empty change sets, etc.
final class InvalidRepoOperationException extends GitHubException {
  const InvalidRepoOperationException(super.message);
}

/// Thrown when GitHub refuses to move a branch because of branch protection
/// (required pull request / reviews / status checks / repository rules).
///
/// Distinct from [BranchChangedException]: retrying cannot help, the change
/// has to go through another branch and a pull request.
final class ProtectedBranchException extends GitHubException {
  final String branchName;

  ProtectedBranchException(this.branchName)
      : super(
          'الفرع "$branchName" محمي ويرفض الدفع المباشر إليه. نفّذ التغيير على '
          'فرع جديد ثم افتح Pull Request، أو عدّل قواعد حماية الفرع من إعدادات '
          'المستودع على GitHub.',
          statusCode: 422,
        );
}
