/// 描述状态主题联想的基本数据模型。
class StatusTopicSuggestion {
  /// 构造函数，接收联想选项的展示文本与真实取值。
  const StatusTopicSuggestion({required this.value, required this.display});

  /// 用户确认联想时写入的实际主题值。
  final String value;

  /// 用于界面展示的无前缀主题文本。
  final String display;
}
