/// 描述状态主题联想的基本数据模型。
class StatusTopicSuggestion {
  /// 构造函数，接收联想选项的展示文本与真实取值。
  const StatusTopicSuggestion({required this.value, required this.display});

  /// 用户确认联想时写入的实际主题值。
  final String value;

  /// 用于界面展示的无前缀主题文本。
  final String display;
}

/// 封装状态主题联想构建逻辑的模型类。
class StatusTopicSuggestionBuilder {
  /// 常量构造函数，允许在全局或状态类中复用实例。
  const StatusTopicSuggestionBuilder();

  static const List<String> _statusSuffixKeywords = <String>[
    'status',
    'state',
    'states',
    'result',
    'results',
    'info',
    'information',
    'detail',
    'details',
    'report',
    'reports',
    'response',
    'responses',
    'update',
    'updates',
    'summary',
    'summaries',
    'overview',
    'metrics',
  ];

  /// 根据命令主题与用户输入计算联想建议。
  Iterable<StatusTopicSuggestion> buildSuggestions({
    required String commandTopic,
    required String input,
  }) {
    final normalizedCommand = _normalizePath(commandTopic.trim());
    final hasCommandTopic = normalizedCommand.isNotEmpty;
    final commandHasSlash = normalizedCommand.contains('/');
    final derivedCommandPrefix = _derivePrefix(
      normalizedCommand,
      hasCommandTopic: hasCommandTopic,
      hasSlash: commandHasSlash,
    );

    final commandCandidates = <String>{};
    if (commandHasSlash) {
      if (derivedCommandPrefix.isNotEmpty) {
        commandCandidates.add(derivedCommandPrefix);
      }
    } else if (hasCommandTopic) {
      commandCandidates.add(normalizedCommand);
    }

    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return const Iterable<StatusTopicSuggestion>.empty();
    }

    if (!trimmed.contains('/')) {
      if (commandCandidates.isEmpty) {
        return const Iterable<StatusTopicSuggestion>.empty();
      }
      final filtered = commandCandidates.where(
        (candidate) =>
            candidate.toLowerCase().startsWith(trimmed.toLowerCase()),
      );
      if (filtered.isEmpty) {
        return const Iterable<StatusTopicSuggestion>.empty();
      }
      return List<StatusTopicSuggestion>.unmodifiable(
        filtered
            .map(
              (path) =>
                  StatusTopicSuggestion(value: path, display: _displayOf(path)),
            )
            .toList(),
      );
    }

    final slashIndex = trimmed.lastIndexOf('/');
    final rawPrefix = slashIndex <= 0 ? '' : trimmed.substring(0, slashIndex);
    final inputPrefix = _normalizePath(rawPrefix);
    final suffix = trimmed.substring(slashIndex + 1);
    final suffixLower = suffix.toLowerCase();

    final prefixCandidates = <String>{};
    prefixCandidates.addAll(commandCandidates);

    final resolvedPrefixes = prefixCandidates.where((candidate) {
      if (inputPrefix.isEmpty) {
        return candidate.isNotEmpty;
      }
      return candidate.toLowerCase().startsWith(inputPrefix.toLowerCase());
    }).toSet();

    if (resolvedPrefixes.isEmpty) {
      return const Iterable<StatusTopicSuggestion>.empty();
    }

    if (suffix.isEmpty) {
      return const Iterable<StatusTopicSuggestion>.empty();
    }

    final filteredSuffixes = _statusSuffixKeywords
        .where((keyword) => keyword.startsWith(suffixLower))
        .toList();

    if (filteredSuffixes.isEmpty) {
      return const Iterable<StatusTopicSuggestion>.empty();
    }

    final suggestions = <StatusTopicSuggestion>[];
    for (final prefix in resolvedPrefixes) {
      final normalizedPrefix = _normalizePath(prefix);
      if (normalizedPrefix.isEmpty) continue;
      for (final suffixCandidate in filteredSuffixes) {
        final suggestionValue = '$normalizedPrefix/$suffixCandidate';
        if (suggestionValue.toLowerCase() == trimmed.toLowerCase()) {
          continue;
        }
        suggestions.add(
          StatusTopicSuggestion(
            value: suggestionValue,
            display: _displayOf(suggestionValue),
          ),
        );
      }
    }

    if (suggestions.isEmpty) {
      return const Iterable<StatusTopicSuggestion>.empty();
    }
    return List<StatusTopicSuggestion>.unmodifiable(suggestions);
  }

  /// 规范化 MQTT 主题路径，移除多余斜杠与尾随斜杠。
  String _normalizePath(String value) {
    final collapsed = value.replaceAll(RegExp(r'/+'), '/').trim();
    if (collapsed.isEmpty || collapsed == '/') {
      return '';
    }
    if (collapsed.endsWith('/') && collapsed.length > 1) {
      return collapsed.substring(0, collapsed.length - 1);
    }
    return collapsed;
  }

  /// 计算命令主题对应的建议前缀。
  String _derivePrefix(
    String normalizedCommand, {
    required bool hasCommandTopic,
    required bool hasSlash,
  }) {
    if (!hasCommandTopic) return '';
    final idx = normalizedCommand.lastIndexOf('/');
    if (idx <= 0) {
      return hasSlash ? '' : normalizedCommand;
    }
    return normalizedCommand.substring(0, idx);
  }

  /// 去除建议展示文本中的前置斜杠，便于界面呈现。
  String _displayOf(String value) {
    return value.startsWith('/') ? value.substring(1) : value;
  }
}
