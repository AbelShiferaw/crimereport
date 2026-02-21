import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:image/image.dart' as img;

import 'package:crimereport/core/constants/app_constants.dart';
import 'package:crimereport/core/theme/colors.dart';

/// Error types for marker image loading.
enum MarkerImageError {
  /// Request timed out
  networkTimeout,
  /// HTTP error or connection failed
  networkError,
  /// Image couldn't be decoded
  decodeError,
  /// Image couldn't be resized
  resizeError,
  /// Fallback asset not found
  assetNotFound,
}

/// Result of marker image loading operation.
class MarkerImageResult {
  /// The loaded image data, or null if failed.
  final Uint8List? data;

  /// Error type if failed, or null if successful.
  final MarkerImageError? error;

  /// Human-readable error message for debugging.
  final String? errorMessage;

  /// Create a successful result with image data.
  const MarkerImageResult.success(Uint8List this.data)
      : error = null,
        errorMessage = null;

  /// Create a failure result with error details.
  const MarkerImageResult.failure(MarkerImageError this.error,
      [this.errorMessage])
      : data = null;

  /// Whether the operation succeeded.
  bool get isSuccess => data != null;
}

/// Parameters for isolate processing.
class _MarkerProcessParams {
  final Uint8List bytes;
  final int borderColorValue;
  final int size;
  final int borderWidth;

  const _MarkerProcessParams({
    required this.bytes,
    required this.borderColorValue,
    required this.size,
    required this.borderWidth,
  });
}

/// Service for loading and caching marker images.
///
/// Features:
/// - Disk caching via flutter_cache_manager (LRU, HTTP-aware)
/// - Rounded square crop with colored border
/// - Background isolate processing to avoid UI jank
/// - In-memory LRU cache for processed images
/// - Granular error reporting
class MarkerImageService {
  /// Singleton instance for shared caching across the app.
  static final MarkerImageService instance = MarkerImageService._();

  MarkerImageService._();

  final _cacheManager = DefaultCacheManager();

  /// LRU cache for processed images using LinkedHashMap with access order.
  /// Max 50 processed images (~50 * 15KB = ~750KB memory)
  final _processedCache = _LruCache<String, Uint8List>(maxSize: 50);

  static const Duration _timeout = Duration(seconds: 10);
  
  /// Corner radius as percentage of size (8% for subtle rounding)
  static const double _cornerRadiusPercent = 0.08;

  /// Load marker image from URL with caching, rounded square crop, and colored border.
  ///
  /// [url] - The image URL to load
  /// [borderColor] - Color for the border (defaults to white)
  ///
  /// Returns [MarkerImageResult] with either the processed image data
  /// or error details for debugging.
  Future<MarkerImageResult> getMarkerImage(
    String url, {
    Color borderColor = const Color(0xFFFFFFFF),
  }) async {
    // Create cache key that includes border color
    final cacheKey = '${url}_${borderColor.toARGB32()}';

    // 1. Check processed cache first (updates LRU order)
    final cached = _processedCache.get(cacheKey);
    if (cached != null) {
      return MarkerImageResult.success(cached);
    }

    try {
      // 2. Get from disk cache (downloads if needed)
      final file = await _cacheManager
          .getSingleFile(url)
          .timeout(_timeout, onTimeout: () {
        throw TimeoutException('Network timeout loading marker image');
      });

      final bytes = await file.readAsBytes();

      // 3. Process in background isolate (rounded square crop + border)
      final params = _MarkerProcessParams(
        bytes: bytes,
        borderColorValue: borderColor.toARGB32(),
        size: AppConstants.mapMarkerSize.toInt(),
        borderWidth: AppConstants.mapMarkerBorderWidth.toInt(),
      );

      final processed = await compute(_processRoundedSquareMarker, params);

      if (processed == null) {
        return const MarkerImageResult.failure(
          MarkerImageError.resizeError,
          'Failed to decode or process image',
        );
      }

      // 4. Cache processed result
      _processedCache.put(cacheKey, processed);
      return MarkerImageResult.success(processed);
    } on TimeoutException catch (e) {
      debugPrint('MarkerImageService: Timeout loading $url');
      return MarkerImageResult.failure(
        MarkerImageError.networkTimeout,
        e.message,
      );
    } on HttpExceptionWithStatus catch (e) {
      debugPrint('MarkerImageService: HTTP ${e.statusCode} for $url');
      return MarkerImageResult.failure(
        MarkerImageError.networkError,
        'HTTP ${e.statusCode}',
      );
    } catch (e) {
      debugPrint('MarkerImageService: Error loading $url: $e');
      return MarkerImageResult.failure(
        MarkerImageError.networkError,
        e.toString(),
      );
    }
  }

  /// Load fallback icon with specified border color.
  ///
  /// Used when thumbnail URL fails to load or is unavailable.
  /// Generates a simple colored rounded square marker.
  Future<MarkerImageResult> loadFallbackIcon({
    Color borderColor = AppColors.primary,
  }) async {
    final cacheKey = '_fallback_${borderColor.toARGB32()}';

    final cached = _processedCache.get(cacheKey);
    if (cached != null) {
      return MarkerImageResult.success(cached);
    }

    // Generate fallback programmatically
    final generated = _generateFallbackMarker(borderColor);
    _processedCache.put(cacheKey, generated);
    return MarkerImageResult.success(generated);
  }

  /// Generate a simple rounded square marker programmatically.
  static Uint8List _generateFallbackMarker(Color borderColor) {
    final size = AppConstants.mapMarkerSize.toInt();
    final borderWidth = AppConstants.mapMarkerBorderWidth.toInt();
    final cornerRadius = (size * _cornerRadiusPercent).round();
    final image = img.Image(width: size, height: size);

    // Fill with transparent
    img.fill(image, color: img.ColorRgba8(0, 0, 0, 0));

    final borderColorImg = img.ColorRgba8(
      (borderColor.r * 255.0).round().clamp(0, 255),
      (borderColor.g * 255.0).round().clamp(0, 255),
      (borderColor.b * 255.0).round().clamp(0, 255),
      (borderColor.a * 255.0).round().clamp(0, 255),
    );

    // Draw outer rounded rectangle (border)
    _fillRoundedRect(image, 0, 0, size, size, cornerRadius, borderColorImg);

    // Draw inner rounded rectangle (dark background)
    final innerCornerRadius = ((size - borderWidth * 2) * _cornerRadiusPercent).round();
    _fillRoundedRect(
      image,
      borderWidth,
      borderWidth,
      size - borderWidth * 2,
      size - borderWidth * 2,
      innerCornerRadius,
      img.ColorRgba8(30, 30, 30, 255),
    );

    // Draw small dot in center as indicator
    final center = size ~/ 2;
    img.fillCircle(
      image,
      x: center,
      y: center,
      radius: 4,
      color: img.ColorRgba8(255, 255, 255, 180),
    );

    return Uint8List.fromList(img.encodePng(image));
  }

  /// Preload multiple images in parallel.
  ///
  /// [urls] - List of image URLs to preload
  /// [borderColors] - Corresponding border colors (must match urls length)
  Future<void> preloadImages(
    List<String> urls, {
    List<Color>? borderColors,
  }) async {
    final colors =
        borderColors ?? List.filled(urls.length, const Color(0xFFFFFFFF));

    await Future.wait(
      List.generate(
          urls.length, (i) => getMarkerImage(urls[i], borderColor: colors[i])),
      eagerError: false,
    );
  }

  /// Clear all in-memory caches.
  void clearMemoryCache() {
    _processedCache.clear();
  }

  /// Clear all caches (memory + disk).
  Future<void> clearAllCaches() async {
    _processedCache.clear();
    await _cacheManager.emptyCache();
  }

  /// Get cache statistics for debugging.
  Map<String, dynamic> get cacheStats => {
        'memoryItems': _processedCache.length,
        'maxMemoryItems': 50,
      };

  /// Process image in isolate: resize, crop to rounded square, add colored border.
  ///
  /// Must be static/top-level to work with [compute].
  static Uint8List? _processRoundedSquareMarker(_MarkerProcessParams params) {
    try {
      final decoded = img.decodeImage(params.bytes);
      if (decoded == null) return null;

      final size = params.size;
      final borderWidth = params.borderWidth;
      final innerSize = size - (borderWidth * 2);
      final outerCornerRadius = (size * _cornerRadiusPercent).round();
      final innerCornerRadius = (innerSize * _cornerRadiusPercent).round();

      // 1. Crop to square (center crop)
      final minDim =
          decoded.width < decoded.height ? decoded.width : decoded.height;
      final cropped = img.copyCrop(
        decoded,
        x: (decoded.width - minDim) ~/ 2,
        y: (decoded.height - minDim) ~/ 2,
        width: minDim,
        height: minDim,
      );

      // 2. Resize to inner size
      final resized = img.copyResize(
        cropped,
        width: innerSize,
        height: innerSize,
        interpolation: img.Interpolation.linear,
      );

      // 3. Create output image with transparency
      final output = img.Image(width: size, height: size);
      img.fill(output, color: img.ColorRgba8(0, 0, 0, 0));

      // 4. Draw border as rounded rectangle (filled with border color)
      final borderColor = params.borderColorValue;
      final borderColorImg = img.ColorRgba8(
        (borderColor >> 16) & 0xFF,
        (borderColor >> 8) & 0xFF,
        borderColor & 0xFF,
        (borderColor >> 24) & 0xFF,
      );
      _fillRoundedRect(output, 0, 0, size, size, outerCornerRadius, borderColorImg);

      // 5. Apply rounded rectangle mask to resized image and composite
      for (int y = 0; y < innerSize; y++) {
        for (int x = 0; x < innerSize; x++) {
          if (_isInsideRoundedRect(x, y, innerSize, innerSize, innerCornerRadius)) {
            final pixel = resized.getPixel(x, y);
            output.setPixel(x + borderWidth, y + borderWidth, pixel);
          }
        }
      }

      return Uint8List.fromList(img.encodePng(output));
    } catch (e) {
      return null;
    }
  }

  /// Fill a rounded rectangle on the image.
  static void _fillRoundedRect(
    img.Image image,
    int x,
    int y,
    int width,
    int height,
    int radius,
    img.Color color,
  ) {
    for (int py = 0; py < height; py++) {
      for (int px = 0; px < width; px++) {
        if (_isInsideRoundedRect(px, py, width, height, radius)) {
          image.setPixel(x + px, y + py, color);
        }
      }
    }
  }

  /// Check if a point is inside a rounded rectangle.
  static bool _isInsideRoundedRect(int x, int y, int w, int h, int r) {
    // Clamp radius to half the smallest dimension
    final effectiveR = r.clamp(0, (w < h ? w : h) ~/ 2);
    
    // Top-left corner
    if (x < effectiveR && y < effectiveR) {
      return _isInsideCircle(x, y, effectiveR, effectiveR, effectiveR);
    }
    // Top-right corner
    if (x >= w - effectiveR && y < effectiveR) {
      return _isInsideCircle(x, y, w - effectiveR - 1, effectiveR, effectiveR);
    }
    // Bottom-left corner
    if (x < effectiveR && y >= h - effectiveR) {
      return _isInsideCircle(x, y, effectiveR, h - effectiveR - 1, effectiveR);
    }
    // Bottom-right corner
    if (x >= w - effectiveR && y >= h - effectiveR) {
      return _isInsideCircle(x, y, w - effectiveR - 1, h - effectiveR - 1, effectiveR);
    }
    // Inside the non-corner rectangular area
    return true;
  }

  /// Check if a point is inside a circle.
  static bool _isInsideCircle(int x, int y, int cx, int cy, int r) {
    final dx = x - cx;
    final dy = y - cy;
    return (dx * dx + dy * dy) <= (r * r);
  }
}

/// Simple LRU cache using LinkedHashMap with access-order tracking.
class _LruCache<K, V> {
  final int maxSize;
  final LinkedHashMap<K, V> _map = LinkedHashMap<K, V>();

  _LruCache({required this.maxSize});

  V? get(K key) {
    final value = _map.remove(key);
    if (value != null) {
      _map[key] = value;
    }
    return value;
  }

  void put(K key, V value) {
    _map.remove(key);
    _map[key] = value;

    while (_map.length > maxSize) {
      final oldestKey = _map.keys.first;
      _map.remove(oldestKey);
    }
  }

  void clear() => _map.clear();

  int get length => _map.length;
}
