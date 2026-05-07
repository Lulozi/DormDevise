import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

typedef ReleaseLinkTapCallback = void Function(String? href);

/// 为 GitHub 发布说明中的链接提供按语义区分的样式。
class GitHubReleaseMarkdownLinkBuilder extends MarkdownElementBuilder {
  GitHubReleaseMarkdownLinkBuilder({
    required this.defaultLinkStyle,
    required this.mentionLinkStyle,
    required this.onTapLink,
  });

  final TextStyle? defaultLinkStyle;
  final TextStyle? mentionLinkStyle;
  final ReleaseLinkTapCallback onTapLink;

  /// 将 markdown 的 a 标签渲染为可点击文本，并按 @用户名 规则切换颜色。
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final String text = element.textContent.trim();
    final String? href = element.attributes['href'];
    final bool isUserMention = _isGitHubMention(text);
    final TextStyle? resolvedStyle =
        (isUserMention ? mentionLinkStyle : defaultLinkStyle) ?? preferredStyle;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => onTapLink(href),
      child: Text(text, style: resolvedStyle),
    );
  }

  /// 识别 GitHub 用户提及文案（@username）。
  bool _isGitHubMention(String text) {
    return RegExp(r'^@[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})$').hasMatch(text);
  }
}
