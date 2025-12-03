import 'package:flutter/material.dart';

/// 颜色工具扩展函数，提供与 ARGB32 编码的转换和通用通道操作。
extension ColorExtensions on Color {
  /// 将 [Color] 转换为 32 位 ARGB 整数（与 Color.value 保持一致）。
  int toARGB32() {
    final int a_ = (a * 255.0).round() & 0xff;
    final int r_ = (r * 255.0).round() & 0xff;
    final int g_ = (g * 255.0).round() & 0xff;
    final int b_ = (b * 255.0).round() & 0xff;
    return (a_ << 24) | (r_ << 16) | (g_ << 8) | b_;
  }

  /// 注意：Color 已经提供 `r`/`g`/`b`/`a` 的浮点通道获取方法（范围 0..1），
  /// 原先的整型 `red`/`green`/`blue`/`alpha` 接口已不推荐使用。
  /// 返回一个通道值可选覆盖的 `Color` 副本（alpha 范围为 0.0 到 1.0）。
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

/// 将 32 位 ARGB 整数转换为 [Color]。
Color colorFromARGB32(int val) => Color(val);

/// 在整型上提供扩展方法，将 ARGB 整数转换为 [Color]。
extension IntToColor on int {
  Color toColor() => Color(this);
}
