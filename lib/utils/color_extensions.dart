import 'package:flutter/material.dart';

/// Utility color helpers and extensions.
extension ColorExtensions on Color {
  /// Convert Color to 32-bit ARGB int like Color.value.
  int toARGB32() {
    final int a_ = (a * 255.0).round() & 0xff;
    final int r_ = (r * 255.0).round() & 0xff;
    final int g_ = (g * 255.0).round() & 0xff;
    final int b_ = (b * 255.0).round() & 0xff;
    return (a_ << 24) | (r_ << 16) | (g_ << 8) | b_;
  }

  /// Note: Color already exposes `r`/`g`/`b`/`a` getters (double 0..1),
  /// and integer `red`/`green`/`blue`/`alpha` are deprecated.
  /// Return a copy of this color with the optionally overridden channel values.
  /// alpha: range [0.0..1.0]
  Color withValues({double? alpha, int? red, int? green, int? blue}) {
    final int resolvedRed = red ?? (r * 255.0).round();
    final int resolvedGreen = green ?? (g * 255.0).round();
    final int resolvedBlue = blue ?? (b * 255.0).round();
    final double resolvedAlpha = alpha ?? a;
    return Color.fromRGBO(
      resolvedRed,
      resolvedGreen,
      resolvedBlue,
      resolvedAlpha,
    );
  }
}

/// Convert an ARGB 32-bit integer back to a [Color].
Color colorFromARGB32(int val) => Color(val);

/// Helper to convert an ARGB int to Color via extension on int.
extension IntToColor on int {
  Color toColor() => Color(this);
}
