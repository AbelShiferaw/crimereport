import 'package:flutter_test/flutter_test.dart';
import 'package:crimereport/core/utils/formatters.dart';

void main() {
  group('Formatters', () {
    group('count', () {
      test('returns raw number below 1000', () {
        expect(Formatters.count(0), '0');
        expect(Formatters.count(1), '1');
        expect(Formatters.count(999), '999');
      });

      test('formats thousands with K suffix', () {
        expect(Formatters.count(1000), '1K');
        expect(Formatters.count(1500), '1.5K');
        expect(Formatters.count(10000), '10K');
        expect(Formatters.count(999999), '1000.0K');
      });

      test('formats millions with M suffix', () {
        expect(Formatters.count(1000000), '1M');
        expect(Formatters.count(1500000), '1.5M');
        expect(Formatters.count(10000000), '10M');
      });

      test('omits decimal when whole number', () {
        expect(Formatters.count(2000), '2K');
        expect(Formatters.count(3000000), '3M');
      });
    });

    group('distance', () {
      test('returns "? mi" for null', () {
        expect(Formatters.distance(null), '? mi');
      });

      test('returns "< 0.1 mi" for very short distances', () {
        expect(Formatters.distance(0.05), '< 0.1 mi');
        expect(Formatters.distance(0.0), '< 0.1 mi');
      });

      test('converts km to miles with 1 decimal', () {
        // 1 km = 0.621371 mi
        expect(Formatters.distance(1.0), '0.6 mi');
        expect(Formatters.distance(10.0), '6.2 mi');
      });
    });

    group('duration', () {
      test('formats zero', () {
        expect(Formatters.duration(0), '0:00');
      });

      test('formats sub-minute', () {
        expect(Formatters.duration(5000), '0:05');
        expect(Formatters.duration(30000), '0:30');
      });

      test('formats minutes and seconds', () {
        expect(Formatters.duration(65000), '1:05');
        expect(Formatters.duration(600000), '10:00');
      });

      test('formats large durations', () {
        expect(Formatters.duration(3600000), '60:00');
      });
    });
  });
}
