import 'package:flutter/material.dart';

/// A named color from the Google Calendar palette.
class PaletteColor {
  const PaletteColor(this.key, this.color, {this.googleEventColorId});

  /// Stable key used for translations ("tomato", "basil", ...).
  final String key;
  final Color color;

  /// Matching Google Calendar event `colorId`, if any.
  final String? googleEventColorId;
}

/// Same 11 colors (and order) as the event color picker of Google Calendar.
const List<PaletteColor> calendarPalette = [
  PaletteColor('tomato', Color(0xFFD50000), googleEventColorId: '11'),
  PaletteColor('flamingo', Color(0xFFE67C73), googleEventColorId: '4'),
  PaletteColor('tangerine', Color(0xFFF4511E), googleEventColorId: '6'),
  PaletteColor('banana', Color(0xFFF6BF26), googleEventColorId: '5'),
  PaletteColor('sage', Color(0xFF33B679), googleEventColorId: '2'),
  PaletteColor('basil', Color(0xFF0B8043), googleEventColorId: '10'),
  PaletteColor('peacock', Color(0xFF039BE5), googleEventColorId: '7'),
  PaletteColor('blueberry', Color(0xFF3F51B5), googleEventColorId: '9'),
  PaletteColor('lavender', Color(0xFF7986CB), googleEventColorId: '1'),
  PaletteColor('grape', Color(0xFF8E24AA), googleEventColorId: '3'),
  PaletteColor('graphite', Color(0xFF616161), googleEventColorId: '8'),
];

const Color googleBlue = Color(0xFF1A73E8);

Color? colorForGoogleEventColorId(String? id) {
  if (id == null) return null;
  for (final p in calendarPalette) {
    if (p.googleEventColorId == id) return p.color;
  }
  return null;
}

/// Closest Google event colorId for an arbitrary color.
String googleEventColorIdFor(Color color) {
  PaletteColor best = calendarPalette.first;
  double bestDist = double.infinity;
  for (final p in calendarPalette) {
    final dr = p.color.r - color.r;
    final dg = p.color.g - color.g;
    final db = p.color.b - color.b;
    final dist = dr * dr + dg * dg + db * db;
    if (dist < bestDist) {
      bestDist = dist;
      best = p;
    }
  }
  return best.googleEventColorId!;
}

Color parseHexColor(String? hex, {Color fallback = googleBlue}) {
  if (hex == null) return fallback;
  var h = hex.trim().replaceFirst('#', '');
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return fallback;
  final v = int.tryParse(h, radix: 16);
  return v == null ? fallback : Color(v);
}

/// Text color readable on top of [background].
Color onColor(Color background) =>
    background.computeLuminance() > 0.55 ? Colors.black87 : Colors.white;
