import 'dart:async';
import 'dart:math' show pow;

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'package:crimereport/core/utils/geo_utils.dart';
import 'package:crimereport/features/feed/data/models/report.dart';
import 'package:crimereport/features/map/presentation/map_constants.dart';

/// Manages the pulsing circle animation that highlights the closest marker
/// to the screen center when zoomed in past the cluster level.
class MapFocusPulse {
  final MapboxMap _mapboxMap;

  CircleAnnotationManager? _pulseManager;
  CircleAnnotation? _focusPulse;
  String? _focusedReportId;
  Timer? _pulseTimer;
  Timer? _periodicUpdateTimer;
  Timer? _stopDetectionTimer;
  double _pulsePhase = 0.0;
  bool _isPulseVisible = false;

  /// Reports to search through. Updated externally when filters change.
  List<Report> reports = [];

  MapFocusPulse(this._mapboxMap);

  /// Must be called after map creation to set up the annotation manager.
  Future<void> setup() async {
    _pulseManager = await _mapboxMap.annotations.createCircleAnnotationManager();
  }

  /// Called on every camera change event. Throttles updates internally.
  void onCameraChanged(CameraChangedEventData data) {
    if (_periodicUpdateTimer == null || !_periodicUpdateTimer!.isActive) {
      _updateFocusPulse();

      _periodicUpdateTimer = Timer.periodic(
        const Duration(milliseconds: 300),
        (_) => _updateFocusPulse(),
      );
    }

    _stopDetectionTimer?.cancel();
    _stopDetectionTimer = Timer(const Duration(milliseconds: 400), () {
      _periodicUpdateTimer?.cancel();
      _periodicUpdateTimer = null;
      _updateFocusPulse();
    });
  }

  Future<void> _updateFocusPulse() async {
    if (_pulseManager == null) return;

    try {
      final cameraState = await _mapboxMap.getCameraState();
      final zoom = cameraState.zoom;

      if (zoom < FocusPulseConfig.minZoom) {
        await hide();
        return;
      }

      final bounds = await _mapboxMap.coordinateBoundsForCamera(
        CameraOptions(center: cameraState.center, zoom: zoom),
      );

      final swLat = bounds.southwest.coordinates.lat.toDouble();
      final swLng = bounds.southwest.coordinates.lng.toDouble();
      final neLat = bounds.northeast.coordinates.lat.toDouble();
      final neLng = bounds.northeast.coordinates.lng.toDouble();

      final visibleReports = reports.where((report) {
        return GeoUtils.isWithinBounds(
          lat: report.latitude,
          lng: report.longitude,
          swLat: swLat,
          swLng: swLng,
          neLat: neLat,
          neLng: neLng,
        );
      }).toList();

      if (visibleReports.isEmpty) {
        await hide();
        return;
      }

      final closest = _findClosest(cameraState.center, visibleReports);
      if (closest == null) {
        await hide();
        return;
      }

      await _showPulse(closest);
    } catch (e) {
      debugPrint('Error in _updateFocusPulse: $e');
    }
  }

  Report? _findClosest(Point center, List<Report> candidates) {
    if (candidates.isEmpty) return null;

    Report? closest;
    double minDistance = double.infinity;

    final centerLat = center.coordinates.lat.toDouble();
    final centerLng = center.coordinates.lng.toDouble();

    for (final report in candidates) {
      final distance = GeoUtils.distanceMeters(
        centerLat,
        centerLng,
        report.latitude,
        report.longitude,
      );
      if (distance < minDistance) {
        minDistance = distance;
        closest = report;
      }
    }

    return closest;
  }

  Future<void> _showPulse(Report report) async {
    if (_pulseManager == null) return;

    final geometry = Point(
      coordinates: Position(report.longitude, report.latitude),
    );
    final color = report.type.color;

    if (_focusedReportId == report.id && _focusPulse != null) {
      if (_pulseTimer == null) _startAnimation();
      return;
    }

    if (_focusPulse != null) {
      try {
        await _pulseManager!.delete(_focusPulse!);
      } catch (e) {
        debugPrint('Error deleting old pulse: $e');
      }
    }

    try {
      _focusPulse = await _pulseManager!.create(
        CircleAnnotationOptions(
          geometry: geometry,
          circleRadius: FocusPulseConfig.minRadius,
          circleColor: color.toARGB32(),
          circleOpacity: FocusPulseConfig.maxOpacity,
          circleBlur: FocusPulseConfig.blur,
        ),
      );

      _focusedReportId = report.id;
      _isPulseVisible = true;
      _startAnimation();
    } catch (e) {
      debugPrint('Failed to create focus pulse: $e');
    }
  }

  Future<void> hide() async {
    if (!_isPulseVisible) return;

    _stopAnimation();

    if (_focusPulse != null && _pulseManager != null) {
      try {
        await _pulseManager!.delete(_focusPulse!);
      } catch (e) {
        debugPrint('Error hiding focus pulse: $e');
      }
      _focusPulse = null;
    }

    _focusedReportId = null;
    _isPulseVisible = false;
  }

  void _startAnimation() {
    if (_pulseTimer != null) return;
    _pulseTimer = Timer.periodic(
      FocusPulseConfig.interval,
      (_) => _animatePulse(),
    );
  }

  void _stopAnimation() {
    _pulseTimer?.cancel();
    _pulseTimer = null;
    _pulsePhase = 0.0;
  }

  Future<void> _animatePulse() async {
    if (_focusPulse == null || _pulseManager == null) return;

    _pulsePhase = (_pulsePhase + FocusPulseConfig.phaseStep) % 1.0;

    final easedPhase = _pulsePhase < 0.5
        ? 2 * _pulsePhase * _pulsePhase
        : 1 - pow(-2 * _pulsePhase + 2, 2) / 2;

    final radius = FocusPulseConfig.minRadius +
        (FocusPulseConfig.maxRadius - FocusPulseConfig.minRadius) * easedPhase;
    final opacity = FocusPulseConfig.maxOpacity * (1.0 - easedPhase * 0.7);

    _focusPulse!.circleRadius = radius;
    _focusPulse!.circleOpacity = opacity;

    try {
      await _pulseManager!.update(_focusPulse!);
    } catch (_) {
      _stopAnimation();
      _focusPulse = null;
      _focusedReportId = null;
      _isPulseVisible = false;
    }
  }

  /// Cancel all timers. Call from the widget's dispose.
  void dispose() {
    _periodicUpdateTimer?.cancel();
    _stopDetectionTimer?.cancel();
    _stopAnimation();
  }
}
