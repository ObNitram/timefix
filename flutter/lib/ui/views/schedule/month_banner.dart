import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../format.dart';
import 'package:intl/intl.dart';

/// Illustrated banner displayed at the start of each month in the schedule
/// view (a drawn landscape whose colors follow the seasons).
class MonthBanner extends StatelessWidget {
  const MonthBanner({super.key, required this.month});

  final DateTime month;

  static const height = 112.0;

  @override
  Widget build(BuildContext context) {
    final palette = _palettes[month.month - 1];
    final now = DateTime.now();
    final pattern = month.year == now.year ? DateFormat.MMMM : DateFormat.yMMMM;
    final label = capitalize(pattern(context.localeName).format(month));
    return Container(
      height: height,
      margin: const EdgeInsets.only(top: 8, bottom: 8),
      child: CustomPaint(
        painter: _LandscapePainter(palette, month.month),
        child: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(72, 16, 16, 0),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w500,
                color: palette.text,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SeasonPalette {
  const _SeasonPalette(this.skyTop, this.skyBottom, this.hillBack, this.hillFront,
      this.sun, this.text);
  final Color skyTop, skyBottom, hillBack, hillFront, sun, text;
}

const _palettes = [
  _SeasonPalette(Color(0xFFB3D4F5), Color(0xFFE8F1FB), Color(0xFFDCE7F2), Color(0xFFFFFFFF), Color(0xFFFFF8E1), Color(0xFF1F3A5F)), // Jan
  _SeasonPalette(Color(0xFFC9B6E4), Color(0xFFF1E7F7), Color(0xFFB79FD6), Color(0xFFEDE3F6), Color(0xFFFFE0EC), Color(0xFF3E2560)), // Feb
  _SeasonPalette(Color(0xFFA8E0D2), Color(0xFFE8F7F2), Color(0xFF7CC4A4), Color(0xFF4FA77F), Color(0xFFFFF59D), Color(0xFF1B4D3E)), // Mar
  _SeasonPalette(Color(0xFFBDE5F8), Color(0xFFF2FAFE), Color(0xFF9CD08B), Color(0xFF6DB65B), Color(0xFFFFEB80), Color(0xFF234F1E)), // Apr
  _SeasonPalette(Color(0xFFFFD6E0), Color(0xFFFFF3F6), Color(0xFF8FD18C), Color(0xFF5EAE5B), Color(0xFFFFB3C7), Color(0xFF4A2030)), // May
  _SeasonPalette(Color(0xFF8ED6F7), Color(0xFFE6F7FE), Color(0xFFF5D06F), Color(0xFF38B2A0), Color(0xFFFFE066), Color(0xFF0E4C5A)), // Jun
  _SeasonPalette(Color(0xFF4FC3F7), Color(0xFFD4F1FD), Color(0xFFF7E1A1), Color(0xFF26A69A), Color(0xFFFFD54F), Color(0xFF053B50)), // Jul
  _SeasonPalette(Color(0xFFFFB74D), Color(0xFFFFE9C7), Color(0xFFE57A44), Color(0xFFB5523B), Color(0xFFFFF3B0), Color(0xFF4A1D0C)), // Aug
  _SeasonPalette(Color(0xFFF7D9A8), Color(0xFFFDF2DF), Color(0xFFD9A441), Color(0xFFA9792B), Color(0xFFFFE8A3), Color(0xFF4D3410)), // Sep
  _SeasonPalette(Color(0xFFF3B27A), Color(0xFFFBE3CC), Color(0xFFC8642C), Color(0xFF8D3B1A), Color(0xFFFFD39A), Color(0xFF3F1606)), // Oct
  _SeasonPalette(Color(0xFFC7B299), Color(0xFFF1E8DD), Color(0xFF9C7A57), Color(0xFF6D4C33), Color(0xFFF5E2C4), Color(0xFF2F1E10)), // Nov
  _SeasonPalette(Color(0xFF34558B), Color(0xFF8FA9D6), Color(0xFFDDE6F3), Color(0xFFFFFFFF), Color(0xFFFFF6D5), Color(0xFFFFFFFF)), // Dec
];

class _LandscapePainter extends CustomPainter {
  _LandscapePainter(this.p, this.seed);
  final _SeasonPalette p;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [p.skyTop, p.skyBottom],
        ).createShader(rect),
    );
    // Sun / moon
    final sunX = size.width * (0.62 + 0.25 * math.sin(seed.toDouble()));
    canvas.drawCircle(Offset(sunX, size.height * 0.32), 16, Paint()..color = p.sun);

    void hill(double baseline, double amplitude, double phase, Color color) {
      final path = Path()..moveTo(0, size.height);
      for (double x = 0; x <= size.width; x += 8) {
        final y = baseline +
            amplitude * math.sin(x / size.width * math.pi * 2.2 + phase) +
            amplitude * 0.4 * math.sin(x / size.width * math.pi * 5.1 + phase * 2);
        path.lineTo(x, y);
      }
      path
        ..lineTo(size.width, size.height)
        ..close();
      canvas.drawPath(path, Paint()..color = color);
    }

    hill(size.height * 0.68, 10, seed * 0.7, p.hillBack);
    hill(size.height * 0.84, 8, seed * 1.3 + 1, p.hillFront);
  }

  @override
  bool shouldRepaint(_LandscapePainter old) => old.seed != seed || old.p != p;
}
