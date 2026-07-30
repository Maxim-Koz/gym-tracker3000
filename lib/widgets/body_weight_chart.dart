import 'package:flutter/material.dart';

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

  String _formatWeight(double weightKg) {
    if (weightKg == weightKg.roundToDouble()) {
      return '${weightKg.toInt()} kg';
    }
    return '${weightKg.toStringAsFixed(1)} kg';
  }

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
          'Latest: ${points.first.weightKg.toStringAsFixed(1)} kg',
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
    var min = weights.reduce((a, b) => a < b ? a : b);
    var max = weights.reduce((a, b) => a > b ? a : b);
    if (min == max) {
      min -= 1;
      max += 1;
    } else {
      final pad = (max - min) * 0.1;
      min -= pad;
      max += pad;
    }
    minWeight = min;
    maxWeight = max;

    firstMs = points.first.date.millisecondsSinceEpoch;
    final lastMs = points.last.date.millisecondsSinceEpoch;
    msSpan = (lastMs - firstMs) == 0 ? 1 : (lastMs - firstMs);
  }

  static const double leftAxisWidth = 44;
  static const double bottomAxisHeight = 20;

  final List<BodyWeightPoint> points;
  final Size size;
  final double chartWidth;
  final double chartHeight;
  late final double minWeight;
  late final double maxWeight;
  late final int firstMs;
  late final int msSpan;

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

    // Horizontal grid lines + weight labels (min / mid / max).
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    final textStyle = TextStyle(color: labelColor, fontSize: 10);
    for (final fraction in [0.0, 0.5, 1.0]) {
      final y = chartHeight - fraction * chartHeight;
      canvas.drawLine(
        Offset(leftAxisWidth, y),
        Offset(size.width, y),
        gridPaint,
      );
      final label = (minWeight + fraction * (maxWeight - minWeight))
          .toStringAsFixed(1);
      final painter = TextPainter(
        text: TextSpan(text: label, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        Offset(0, (y - painter.height / 2).clamp(0, size.height)),
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

  @override
  bool shouldRepaint(covariant _BodyWeightChartPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.selectedIndex != selectedIndex;
  }
}
