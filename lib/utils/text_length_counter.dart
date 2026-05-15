/// 统一的文本长度计数工具：英文/半角算 1，中文/全角算 2。
class TextLengthCounter {
  const TextLengthCounter._();

  /// 按半角单位统计文本长度。
  static int computeHalfWidthUnits(String text) {
    int units = 0;
    for (final int rune in text.runes) {
      units += _unitWeight(rune);
    }
    return units;
  }

  /// ASCII 视为半角 1，其余视为全角 2。
  static int _unitWeight(int rune) {
    return rune <= 0x7F ? 1 : 2;
  }
}
