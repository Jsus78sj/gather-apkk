/// نتيجة إنشاء Pull Request بعد تحويل الدفع من فرع محمي إلى فرع جديد.
class CreatedPullRequestResult {
  final int number;
  final String title;
  final String htmlUrl;
  final String headBranch;
  final String baseBranch;

  const CreatedPullRequestResult({
    required this.number,
    required this.title,
    required this.htmlUrl,
    required this.headBranch,
    required this.baseBranch,
  });

  factory CreatedPullRequestResult.fromJson(
    Map<String, dynamic> json, {
    required String headBranch,
    required String baseBranch,
  }) {
    return CreatedPullRequestResult(
      number: (json['number'] as num?)?.toInt() ?? 0,
      title: (json['title'] as String?) ?? '',
      htmlUrl: (json['html_url'] as String?) ?? '',
      headBranch: headBranch,
      baseBranch: baseBranch,
    );
  }
}
