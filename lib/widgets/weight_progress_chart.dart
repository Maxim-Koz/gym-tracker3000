import 'package:flutter/material.dart';

/// A single point on the weight-progress graph: a session date paired with
/// the heaviest weight (in kg) logged that session.
class WeightPoint {
  final DateTime date;
  final double weightKg;

  const WeightPoint({required this.date, required this.weightKg});
}

/// Plots [points] as a simple line chart: time on the x-axis, weight on the
/// y-axis (always starting at 0), points connected with straight lines.
/// Long-pressing (and dragging while held) shows the date and weight for the
/// nearest point. Built with a CustomPainter so no charting package
/// dependency is required.
class WeightProgressChart extends StatefulWidget {
  final List<WeightPoint> points;

  const WeightProgressChart({super.key, required this.points});

  @override
  State<WeightProgressChart> createState() => _WeightProgressChartState();
}

class _WeightProgressChartState extends State<WeightProgressChart> {
  int? _highlightedIndex;

  void _updateHighlight(Offset localPosition, _ChartGeometry geometry) {
    final index = geometry.nearestIndex(localPosition.dx);
    if (index != _highlightedIndex) {
      setState(() => _highlightedIndex = index);
    }
  }

  void _clearHighlight() {
    if (_highlightedIndex != null) {
      setState(() => _highlightedIndex = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final points = widget.points;
    if (points.isEmpty) {
      return const Center(child: Text('No sets recorded in this range.'));
    }
    if (points.length == 1) {
      final p = points.first;
      return Center(
        child: Text(
          'Only one data point in this range\n'
          '(${p.weightKg.toStringAsFixed(1)} kg on '
          '${p.date.day}/${p.date.month}/${p.date.year})',
          textAlign: TextAlign.center,
        ),
      );
    }

    final scheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final geometry = _ChartGeometry(points: points, size: size);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPressStart: (details) =>
              _updateHighlight(details.localPosition, geometry),
          onLongPressMoveUpdate: (details) =>
              _updateHighlight(details.localPosition, geometry),
          onLongPressEnd: (_) => _clearHighlight(),
          onLongPressCancel: _clearHighlight,
          child: CustomPaint(
            size: size,
            painter: _WeightChartPainter(
              geometry: geometry,
              highlightedIndex: _highlightedIndex,
              axisColor: scheme.onSurfaceVariant,
              gridColor: scheme.surfaceContainerHighest,
              lineColor: scheme.primary,
              pointColor: scheme.primary,
              tooltipBackground: scheme.inverseSurface,
              tooltipTextColor: scheme.onInverseSurface,
            ),
          ),
        );
      },
    );
  }
}

/// Shared coordinate mapping between the painter and the gesture handler, so
/// hit-testing always agrees with what's drawn. The y-axis always starts at
/// 0 kg; the top of the chart is the max logged weight plus a little
/// headroom.
class _ChartGeometry {
  final List<WeightPoint> points;
  final Size size;

  static const double leftPadding = 46.0;
  static const double rightPadding = 12.0;
  static const double topPadding = 12.0;
  static const double bottomPadding = 26.0;

  late final double chartWidth;
  late final double chartHeight;
  late final DateTime minDate;
  late final DateTime maxDate;
  late final int dateRangeMs;
  late final double maxWeight;

  _ChartGeometry({required this.points, required this.size}) {
    chartWidth = size.width - leftPadding - rightPadding;
    chartHeight = size.height - topPadding - bottomPadding;
    minDate = points.first.date;
    maxDate = points.last.date;
    dateRangeMs = maxDate.difference(minDate).inMilliseconds;

    final rawMax = points
        .map((p) => p.weightKg)
        .reduce((a, b) => a > b ? a : b);
    maxWeight = rawMax <= 0 ? 10 : rawMax * 1.15;
  }

  Offset offsetFor(WeightPoint p) {
    final xFraction = dateRangeMs == 0
        ? 0.5
        : p.date.difference(minDate).inMilliseconds / dateRangeMs;
    final yFraction = maxWeight == 0 ? 0.0 : p.weightKg / maxWeight;
    final safeChartWidth = chartWidth < 0 ? 0.0 : chartWidth;
    final safeChartHeight = chartHeight < 0 ? 0.0 : chartHeight;
    return Offset(
      leftPadding + xFraction * safeChartWidth,
      topPadding + (1 - yFraction) * safeChartHeight,
    );
  }

  int nearestIndex(double dx) {
    var bestIndex = 0;
    var bestDistance = double.infinity;
    for (var i = 0; i < points.length; i++) {
      final pointX = offsetFor(points[i]).dx;
      final distance = (pointX - dx).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }
    return bestIndex;
  }
}

class _WeightChartPainter extends CustomPainter {
  final _ChartGeometry geometry;
  final int? highlightedIndex;
  final Color axisColor;
  final Color gridColor;
  final Color lineColor;
  final Color pointColor;
  final Color tooltipBackground;
  final Color tooltipTextColor;

  _WeightChartPainter({
    required this.geometry,
    required this.highlightedIndex,
    required this.axisColor,
    required this.gridColor,
    required this.lineColor,
    required this.pointColor,
    required this.tooltipBackground,
    required this.tooltipTextColor,
  });

  static const int _gridLines = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final points = geometry.points;
    final leftPadding = _ChartGeometry.leftPadding;
    final topPadding = _ChartGeometry.topPadding;
    final chartWidth = geometry.chartWidth;
    final chartHeight = geometry.chartHeight;
    if (chartWidth <= 0 || chartHeight <= 0) return;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    final labelStyle = TextStyle(color: axisColor, fontSize: 10);

    // Horizontal grid lines + y-axis (weight) labels. Bottom line is 0 kg.
    for (var i = 0; i <= _gridLines; i++) {
      final fraction = i / _gridLines;
      final y = topPadding + fraction * chartHeight;
      canvas.drawLine(
        Offset(leftPadding, y),
        Offset(leftPadding + chartWidth, y),
        gridPaint,
      );
      final weightValue = geometry.maxWeight * (1 - fraction);
      final tp = TextPainter(
        text: TextSpan(
          text: '${weightValue.toStringAsFixed(1)} kg',
          style: labelStyle,
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(leftPadding - tp.width - 6, y - tp.height / 2));
    }

    // X-axis (date) labels: first, middle, last point.
    final labelIndices = <int>{0, points.length - 1};
    if (points.length > 2) labelIndices.add(points.length ~/ 2);
    for (final index in labelIndices) {
      final p = points[index];
      final pos = geometry.offsetFor(p);
      final label = '${p.date.day}/${p.date.month}/${p.date.year % 100}';
      final tp = TextPainter(
        text: TextSpan(text: label, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      var dx = pos.dx - tp.width / 2;
      if (dx < leftPadding) dx = leftPadding;
      if (dx + tp.width > leftPadding + chartWidth) {
        dx = leftPadding + chartWidth - tp.width;
      }
      tp.paint(canvas, Offset(dx, topPadding + chartHeight + 6));
    }

    // Line connecting the points (straight segments).
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final offset = geometry.offsetFor(points[i]);
      if (i == 0) {
        path.moveTo(offset.dx, offset.dy);
      } else {
        path.lineTo(offset.dx, offset.dy);
      }
    }
    canvas.drawPath(path, linePaint);

    // Point markers, with the held point drawn larger plus a soft halo.
    final pointPaint = Paint()..color = pointColor;
    for (var i = 0; i < points.length; i++) {
      final offset = geometry.offsetFor(points[i]);
      final isHighlighted = i == highlightedIndex;
      if (isHighlighted) {
        final haloPaint = Paint()..color = pointColor.withOpacity(0.25);
        canvas.drawCircle(offset, 11, haloPaint);
      }
      canvas.drawCircle(offset, isHighlighted ? 5.5 : 3.5, pointPaint);
    }

    // Tooltip for the held point: a dashed guide line plus a bubble showing
    // the date and weight.
    if (highlightedIndex != null) {
      final p = points[highlightedIndex!];
      final pos = geometry.offsetFor(p);

      _drawDashedLine(
        canvas,
        Offset(pos.dx, topPadding),
        Offset(pos.dx, topPadding + chartHeight),
        gridPaint,
      );

      final dateLabel = '${p.date.day}/${p.date.month}/${p.date.year}';
      final weightLabel = '${p.weightKg.toStringAsFixed(1)} kg';

      final dateSpan = TextPainter(
        text: TextSpan(
          text: dateLabel,
          style: TextStyle(
            color: tooltipTextColor,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final weightSpan = TextPainter(
        text: TextSpan(
          text: weightLabel,
          style: TextStyle(color: tooltipTextColor, fontSize: 11),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      const hPad = 8.0;
      const vPad = 6.0;
      const gap = 2.0;
      final bubbleWidth =
          (dateSpan.width > weightSpan.width
              ? dateSpan.width
              : weightSpan.width) +
          hPad * 2;
      final bubbleHeight = dateSpan.height + weightSpan.height + gap + vPad * 2;

      var bubbleLeft = pos.dx - bubbleWidth / 2;
      if (bubbleLeft < 0) bubbleLeft = 0;
      if (bubbleLeft + bubbleWidth > size.width) {
        bubbleLeft = size.width - bubbleWidth;
      }

      var bubbleTop = pos.dy - bubbleHeight - 12;
      if (bubbleTop < 0) {
        // Not enough room above the point; show the bubble below it instead.
        bubbleTop = pos.dy + 12;
      }

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(bubbleLeft, bubbleTop, bubbleWidth, bubbleHeight),
        const Radius.circular(6),
      );
      canvas.drawRRect(rect, Paint()..color = tooltipBackground);

      dateSpan.paint(canvas, Offset(bubbleLeft + hPad, bubbleTop + vPad));
      weightSpan.paint(
        canvas,
        Offset(bubbleLeft + hPad, bubbleTop + vPad + dateSpan.height + gap),
      );
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
  bool shouldRepaint(covariant _WeightChartPainter oldDelegate) {
    return oldDelegate.geometry.points != geometry.points ||
        oldDelegate.highlightedIndex != highlightedIndex ||
        oldDelegate.axisColor != axisColor ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.pointColor != pointColor;
  }
}
