import 'package:dormdevise/utils/person_identity.dart';
import 'package:flutter/material.dart';

/// 计算昵称/签名文本行高，确保头像信息区垂直对齐结果稳定。
double _measureAvatarInfoLineHeight(TextStyle style) {
  final TextPainter painter = TextPainter(
    text: TextSpan(text: '骨', style: style),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  final List<LineMetrics> metrics = painter.computeLineMetrics();
  if (metrics.isNotEmpty) {
    return metrics.first.height;
  }
  return style.fontSize ?? 14;
}

/// 计算头像信息区签名顶部间距。
///
/// 双行签名时满足：昵称 + 间距 + 两行签名高度 = 头像高度，
/// 以保证第二行底部与头像底部视觉对齐。
double computeAvatarInfoSignatureTopGap({
  required double avatarSize,
  required TextStyle nicknameStyle,
  required TextStyle signatureStyle,
  required bool twoLines,
}) {
  final double nicknameLineHeight = _measureAvatarInfoLineHeight(nicknameStyle);
  final double signatureLineHeight = _measureAvatarInfoLineHeight(
    signatureStyle,
  );
  final double targetGap =
      avatarSize - nicknameLineHeight - signatureLineHeight * 2;
  final double twoLineGap = targetGap.clamp(0.0, 4.0).toDouble();
  if (twoLines) {
    return twoLineGap;
  }
  final double singleLineCenteredGap = twoLineGap + signatureLineHeight / 2;
  return singleLineCenteredGap.clamp(0.0, 12.0).toDouble();
}

/// 按 13 个中文字符宽度阈值格式化头像信息区签名。
///
/// 返回值为 (格式化后的签名, 是否双行)。
(String, bool) formatSignatureForAvatarInfo(
  String signature, {
  int maxCharsPerLine = 13,
}) {
  final String normalized = signature.trim().isEmpty
      ? kDefaultSignatureText
      : signature.trim();
  final List<int> runeList = normalized.runes.toList(growable: false);
  double weightedLength = 0;
  int splitIndex = -1;
  for (int i = 0; i < runeList.length; i++) {
    final int rune = runeList[i];
    weightedLength += _isAvatarInfoCjkRune(rune) ? 1.0 : 0.5;
    if (weightedLength > maxCharsPerLine) {
      splitIndex = i;
      break;
    }
  }
  if (splitIndex == -1) {
    return (normalized, false);
  }
  final String firstLine = String.fromCharCodes(runeList.take(splitIndex));
  final String secondLine = String.fromCharCodes(runeList.skip(splitIndex));
  return ('$firstLine\n$secondLine', true);
}

/// 按 13 个中文字符宽度阈值格式化设置页签名展示。
String formatSignatureForSettingsDisplay(
  String signature, {
  int maxCharsPerLine = 13,
}) {
  final String normalized = signature.trim().isEmpty
      ? kDefaultSignatureText
      : signature.trim();
  final List<String> lines = <String>[];
  StringBuffer currentLine = StringBuffer();
  double weightedLength = 0;

  for (final int rune in normalized.runes) {
    final double runeWeight = _isAvatarInfoCjkRune(rune) ? 1.0 : 0.5;
    // 到达单行阈值后换行，确保每行最多13个中文字符宽度。
    if (weightedLength + runeWeight > maxCharsPerLine &&
        currentLine.isNotEmpty) {
      lines.add(currentLine.toString());
      currentLine = StringBuffer();
      weightedLength = 0;
    }
    currentLine.writeCharCode(rune);
    weightedLength += runeWeight;
  }

  if (currentLine.isNotEmpty) {
    lines.add(currentLine.toString());
  }
  return lines.join('\n');
}

bool _isAvatarInfoCjkRune(int rune) {
  return (rune >= 0x4E00 && rune <= 0x9FFF) ||
      (rune >= 0x3400 && rune <= 0x4DBF) ||
      (rune >= 0xF900 && rune <= 0xFAFF);
}
