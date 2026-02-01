/// Utility class for formatting values throughout the app.
class Formatters {
  Formatters._(); // Private constructor

  /// Formats a count with K/M suffixes for large numbers.
  /// Examples: 999 → "999", 1500 → "1.5K", 1500000 → "1.5M"
  static String count(int count) {
    if (count >= 1000000) {
      final value = count / 1000000;
      return '${value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 1)}M';
    }
    if (count >= 1000) {
      final value = count / 1000;
      return '${value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 1)}K';
    }
    return count.toString();
  }

  /// Formats distance in kilometers to miles.
  /// Examples: null → "? mi", 0.05 → "< 0.1 mi", 1.5 → "0.9 mi"
  static String distance(double? km) {
    if (km == null) return '? mi';
    final miles = km * 0.621371;
    if (miles < 0.1) return '< 0.1 mi';
    return '${miles.toStringAsFixed(1)} mi';
  }

  /// Formats a duration in milliseconds to mm:ss.
  /// Examples: 65000 → "1:05", 3600000 → "60:00"
  static String duration(int milliseconds) {
    final seconds = (milliseconds / 1000).floor();
    final minutes = (seconds / 60).floor();
    final remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }
}
