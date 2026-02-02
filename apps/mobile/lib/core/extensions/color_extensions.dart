import 'package:flutter/material.dart';

/// Extensions for Flutter Color class.
extension ColorExtensions on Color {
  /// Converts Flutter Color to ARGB32 int format for Mapbox SDK.
  ///
  /// Mapbox expects colors as 32-bit ARGB integers.
  int toARGB32() {
    return (a.toInt() << 24) | (r.toInt() << 16) | (g.toInt() << 8) | b.toInt();
  }
}
