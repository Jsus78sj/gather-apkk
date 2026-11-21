/// Client-side guard for GitHub's code-search quota.
///
/// The Search API allows only about 9-10 code searches per minute, and a
/// rejected request still counts. Searches are therefore counted locally and
/// refused (with the time to wait) before they reach the network.
class SearchRateLimiter {
  /// Requests allowed inside [window]. Kept below GitHub's real limit.
  final int maxRequests;
  final Duration window;
  final DateTime Function() _now;
  final List<DateTime> _stamps = <DateTime>[];

  SearchRateLimiter({
    this.maxRequests = 8,
    this.window = const Duration(minutes: 1),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// How long to wait before the next request is allowed, or `null` when one
  /// can be sent right now.
  Duration? waitTime() {
    final now = _now();
    _stamps.removeWhere((stamp) => now.difference(stamp) >= window);
    if (_stamps.length < maxRequests) return null;
    return window - now.difference(_stamps.first);
  }

  /// Counts a request that is about to be sent.
  void record() => _stamps.add(_now());
}
