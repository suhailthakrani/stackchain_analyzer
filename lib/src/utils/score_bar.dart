/// Visual score bar helpers for terminal output.
abstract final class ScoreBar {
  static String render(int score, {int width = 10}) {
    final clamped = score.clamp(0, 100);
    final filled = ((clamped / 100) * width).round().clamp(0, width);
    final empty = width - filled;
    return '${'█' * filled}${'░' * empty}';
  }
}
