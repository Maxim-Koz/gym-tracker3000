import 'package:flutter/material.dart';
import 'package:gym_tracker/services/weight_format.dart';
import 'dart:math' as math;

class BodyWeightPoint {
  const BodyWeightPoint({required this.date, required this.weightKg});

  final DateTime date;
  final double weightKg;
}

/// Simple line chart of body weight over time. Expects [points] sorted
/// oldest-to-newest, already normalized to a single unit (kg) so mixed
/// kg/lb entries plot on the same scale.
///
/// Holding a finger/mouse down on the chart shows a tooltip with the exact
/// date and weight for the nearest point, mirroring the exercise progress
/// graph's long-press behaviour.
class BodyWeightChart extends StatefulWidget {
  const BodyWeightChart({super.key, required this.points});

  final List<BodyWeightPoint> points;

  @override
  State<BodyWeightChart> createState() => _BodyWeightChartState();
}

class _BodyWeightChartState extends State<BodyWeightChart> {
  int? _selectedIndex;

  void _updateSelection(_ChartGeometry geometry, Offset localPosition) {
    final index = geometry.nearestIndex(localPosition);
    if (index != _selectedIndex) {
      setState(() => _selectedIndex = index);
    }
  }

  void _clearSelection() {
    if (_selectedIndex != null) {
      setState(() => _selectedIndex = null);
    }
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final local = date.toLocal();
    return '${local.day} ${months[local.month - 1]} ${local.year}';
  }

  String _formatWeight(double weightKg) => '${formatWeight(weightKg)} kg';

  @override
  Widget build(BuildContext context) {
    final points = widget.points;
    if (points.isEmpty) {
      return const Center(child: Text('No weight entries logged yet.'));
    }
    if (points.length == 1) {
      return Center(
        child: Text(
          'Log another entry to see a trend.\n'
          'Latest: ${formatWeight(points.first.weightKg)} kg',
          textAlign: TextAlign.center,
        ),
      );
    }

    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final geometry = _ChartGeometry(points: points, size: size);
          final selectedIndex = _selectedIndex;

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPressStart: (details) =>
                _updateSelection(geometry, details.localPosition),
            onLongPressMoveUpdate: (details) =>
                _updateSelection(geometry, details.localPosition),
            onLongPressEnd: (_) => _clearSelection(),
            onLongPressCancel: _clearSelection,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                CustomPaint(
                  size: size,
                  painter: _BodyWeightChartPainter(
                    points: points,
                    geometry: geometry,
                    selectedIndex: selectedIndex,
                    lineColor: scheme.primary,
                    fillColor: scheme.primary.withValues(alpha: 0.12),
                    gridColor: scheme.outlineVariant,
                    labelColor: scheme.onSurfaceVariant,
                  ),
                ),
                if (selectedIndex != null)
                  _Tooltip(
                    anchor: geometry.offsetFor(selectedIndex),
                    chartSize: size,
                    backgroundColor: scheme.inverseSurface,
                    textColor: scheme.onInverseSurface,
                    dateText: _formatDate(points[selectedIndex].date),
                    weightText: _formatWeight(points[selectedIndex].weightKg),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Tooltip extends StatelessWidget {
  const _Tooltip({
    required this.anchor,
    required this.chartSize,
    required this.backgroundColor,
    required this.textColor,
    required this.dateText,
    required this.weightText,
  });

  final Offset anchor;
  final Size chartSize;
  final Color backgroundColor;
  final Color textColor;
  final String dateText;
  final String weightText;

  static const double _width = 116;
  static const double _height = 46;
  static const double _verticalGap = 12;

  @override
  Widget build(BuildContext context) {
    // Center the tooltip horizontally on the point, clamped so it stays
    // within the chart's bounds.
    var left = anchor.dx - _width / 2;
    left = left.clamp(
      0.0,
      (chartSize.width - _width).clamp(0.0, double.infinity),
    );

    // Prefer showing above the point; flip below if there isn't room.
    final showAbove = anchor.dy - _verticalGap - _height >= 0;
    final top = showAbove
        ? anchor.dy - _verticalGap - _height
        : anchor.dy + _verticalGap;

    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: Container(
          width: _width,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                weightText,
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              Text(dateText, style: TextStyle(color: textColor, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shared coordinate mapping between the painter and hit-testing, so the
/// two never drift out of sync.
class _ChartGeometry {
  _ChartGeometry({required this.points, required this.size})
    : chartWidth = size.width - leftAxisWidth,
      chartHeight = size.height - bottomAxisHeight {
    final weights = points.map((p) => p.weightKg).toList();
    final rawMin = weights.reduce((a, b) => a < b ? a : b);
    final rawMax = weights.reduce((a, b) => a > b ? a : b);
    hasNegativeValues = rawMin < 0;

    double min;
    double max;
    if (hasNegativeValues) {
      final visibleMax = rawMax > 0 ? rawMax : 0.0;
      final span = visibleMax - rawMin;
      final pad = span == 0 ? 1.0 : span * 0.1;
      min = rawMin - pad;
      max = visibleMax + pad;
    } else {
      // Keep 0kg anchored at the bottom whenever all values are >= 0.
      final visibleMax = rawMax <= 0 ? 1.0 : rawMax;
      final padTop = visibleMax == 0 ? 1.0 : visibleMax * 0.1;
      min = 0;
      max = visibleMax + padTop;
    }

    final step = _niceStep(max - min, targetTickCount: 4);
    minWeight = hasNegativeValues ? _floorToStep(min, step) : 0;
    maxWeight = _ceilToStep(max, step);
    tickStep = step;
    if (maxWeight <= minWeight) {
      maxWeight = minWeight + tickStep;
    }

    firstMs = points.first.date.millisecondsSinceEpoch;
    final lastMs = points.last.date.millisecondsSinceEpoch;
    msSpan = (lastMs - firstMs) == 0 ? 1 : (lastMs - firstMs);
  }

  static const double leftAxisWidth = 52;
  static const double bottomAxisHeight = 20;

  final List<BodyWeightPoint> points;
  final Size size;
  final double chartWidth;
  final double chartHeight;
  late final double minWeight;
  late double maxWeight;
  late final bool hasNegativeValues;
  late final double tickStep;
  late final int firstMs;
  late final int msSpan;

  static double _niceStep(double range, {int targetTickCount = 4}) {
    if (range <= 0) return 1;
    final roughStep = range / targetTickCount;
    final magnitude = math.pow(10, (math.log(roughStep) / math.ln10).floor());
    final residual = roughStep / magnitude;

    final niceResidual = residual <= 1
        ? 1.0
        : residual <= 2
        ? 2.0
        : residual <= 2.5
        ? 2.5
        : residual <= 5
        ? 5.0
        : 10.0;
    return niceResidual * magnitude;
  }

  static double _floorToStep(double value, double step) {
    return (value / step).floorToDouble() * step;
  }

  static double _ceilToStep(double value, double step) {
    return (value / step).ceilToDouble() * step;
  }

  List<double> get yTicks {
    final ticks = <double>[];
    var value = minWeight;
    final limit = maxWeight + tickStep * 0.5;
    while (value <= limit) {
      ticks.add(value);
      value += tickStep;
    }
    return ticks;
  }

  Offset offsetFor(int index) {
    final p = points[index];
    final xRatio = (p.date.millisecondsSinceEpoch - firstMs) / msSpan;
    final yRatio = (p.weightKg - minWeight) / (maxWeight - minWeight);
    return Offset(
      leftAxisWidth + xRatio * chartWidth,
      chartHeight - yRatio * chartHeight,
    );
  }

  /// Finds the point whose x-position is closest to [localPosition], which
  /// feels more natural to drag across than requiring an exact y match too.
  int nearestIndex(Offset localPosition) {
    var closestIndex = 0;
    var closestDistance = double.infinity;
    for (var i = 0; i < points.length; i++) {
      final dx = (offsetFor(i).dx - localPosition.dx).abs();
      if (dx < closestDistance) {
        closestDistance = dx;
        closestIndex = i;
      }
    }
    return closestIndex;
  }

  double? get zeroLineY {
    if (!hasNegativeValues) return null;
    final weightRange = maxWeight - minWeight;
    if (weightRange == 0) return null;
    final yRatio = (0 - minWeight) / weightRange;
    return chartHeight - yRatio * chartHeight;
  }
}

class _BodyWeightChartPainter extends CustomPainter {
  _BodyWeightChartPainter({
    required this.points,
    required this.geometry,
    required this.selectedIndex,
    required this.lineColor,
    required this.fillColor,
    required this.gridColor,
    required this.labelColor,
  });

  final List<BodyWeightPoint> points;
  final _ChartGeometry geometry;
  final int? selectedIndex;
  final Color lineColor;
  final Color fillColor;
  final Color gridColor;
  final Color labelColor;

  @override
  void paint(Canvas canvas, Size size) {
    final chartWidth = geometry.chartWidth;
    final chartHeight = geometry.chartHeight;
    if (chartWidth <= 0 || chartHeight <= 0) return;

    final minWeight = geometry.minWeight;
    final maxWeight = geometry.maxWeight;
    final leftAxisWidth = _ChartGeometry.leftAxisWidth;

    // Horizontal grid lines + weight labels at clean increments.
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    final textStyle = TextStyle(color: labelColor, fontSize: 10);
    for (final tickValue in geometry.yTicks) {
      final fraction = (tickValue - minWeight) / (maxWeight - minWeight);
      final y = chartHeight - fraction * chartHeight;
      canvas.drawLine(
        Offset(leftAxisWidth, y),
        Offset(size.width, y),
        gridPaint,
      );
      final label = '${tickValue.toStringAsFixed(1)} kg';
      final painter = TextPainter(
        text: TextSpan(text: label, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        Offset(0, (y - painter.height / 2).clamp(0, size.height)),
      );
    }

    final zeroLineY = geometry.zeroLineY;
    if (zeroLineY != null) {
      final zeroPaint = Paint()
        ..color = labelColor.withValues(alpha: 0.7)
        ..strokeWidth = 1.2;
      _drawDashedLine(
        canvas,
        Offset(leftAxisWidth, zeroLineY),
        Offset(size.width, zeroLineY),
        zeroPaint,
      );
    }

    // Date labels for first and last point.
    void paintDateLabel(DateTime date, double x, {bool alignRight = false}) {
      final label = '${date.day}/${date.month}';
      final painter = TextPainter(
        text: TextSpan(text: label, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      final dx = alignRight ? x - painter.width : x;
      painter.paint(canvas, Offset(dx, chartHeight + 4));
    }

    paintDateLabel(points.first.date, leftAxisWidth);
    paintDateLabel(points.last.date, size.width, alignRight: true);

    // Line + filled area under it.
    final linePath = Path();
    final fillPath = Path();
    for (var i = 0; i < points.length; i++) {
      final offset = geometry.offsetFor(i);
      if (i == 0) {
        linePath.moveTo(offset.dx, offset.dy);
        fillPath.moveTo(offset.dx, chartHeight);
        fillPath.lineTo(offset.dx, offset.dy);
      } else {
        linePath.lineTo(offset.dx, offset.dy);
        fillPath.lineTo(offset.dx, offset.dy);
      }
    }
    fillPath.lineTo(geometry.offsetFor(points.length - 1).dx, chartHeight);
    fillPath.close();

    canvas.drawPath(fillPath, Paint()..color = fillColor);
    canvas.drawPath(
      linePath,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    // Dots at each point (the selected one drawn larger, with a vertical
    // guide line down to the date axis).
    final dotPaint = Paint()..color = lineColor;
    for (var i = 0; i < points.length; i++) {
      final offset = geometry.offsetFor(i);
      final isSelected = i == selectedIndex;
      if (isSelected) {
        canvas.drawLine(
          Offset(offset.dx, 0),
          Offset(offset.dx, chartHeight),
          Paint()
            ..color = lineColor.withValues(alpha: 0.4)
            ..strokeWidth = 1,
        );
        canvas.drawCircle(offset, 6, Paint()..color = fillColor);
        canvas.drawCircle(
          offset,
          5,
          Paint()
            ..color = lineColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      } else {
        canvas.drawCircle(offset, 3, dotPaint);
      }
    }
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const dashLength = 4.0;
    const gapLength = 3.0;
    final totalDistance = (end - start).distance;
    if (totalDistance == 0) return;

    final direction = (end - start) / totalDistance;
    var distanceCovered = 0.0;
    while (distanceCovered < totalDistance) {
      final segmentEnd = (distanceCovered + dashLength > totalDistance)
          ? totalDistance
          : distanceCovered + dashLength;
      canvas.drawLine(
        start + direction * distanceCovered,
        start + direction * segmentEnd,
        paint,
      );
      distanceCovered += dashLength + gapLength;
    }
  }

  @override
  bool shouldRepaint(covariant _BodyWeightChartPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.selectedIndex != selectedIndex;
  }
}
