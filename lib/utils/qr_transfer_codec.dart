import 'dart:convert';
import 'dart:io';

/// 二维码传输负载的统一编解码工具。
class QrTransferCodec {
  static const String _prefix = 'ddv';

  /// 将任意文本压缩编码为适合二维码传输的短字符串。
  static String encodeText({
    required String type,
    required String text,
    int version = 1,
  }) {
    final List<int> compressed = gzip.encode(utf8.encode(text));
    final String encoded = base64Url.encode(compressed).replaceAll('=', '');
    return '$_prefix:$type:$version:$encoded';
  }

  /// 将 JSON 对象压缩编码为二维码字符串。
  static String encodeJson({
    required String type,
    required Object payload,
    int version = 1,
  }) {
    return encodeText(type: type, text: jsonEncode(payload), version: version);
  }

  /// 尝试将二维码内容恢复为原始文本；若不是本应用编码则原样返回。
  static String decodeText(String raw) {
    final DecodedQrTransferPayload? decoded = tryDecode(raw);
    return decoded?.text ?? raw.trim();
  }

  /// 解析二维码负载；若不是本应用编码则返回 `null`。
  static DecodedQrTransferPayload? tryDecode(String raw) {
    final String trimmed = raw.trim();
    if (!trimmed.startsWith('$_prefix:')) {
      return null;
    }

    final List<String> parts = trimmed.split(':');
    if (parts.length < 4) {
      throw const FormatException('二维码内容不完整');
    }

    final int version = int.tryParse(parts[2]) ?? 0;
    if (version <= 0) {
      throw const FormatException('二维码版本无效');
    }

    final String encoded = parts.sublist(3).join(':');
    final List<int> compressed = base64Url.decode(_restorePadding(encoded));
    final String text = utf8.decode(gzip.decode(compressed));
    return DecodedQrTransferPayload(
      type: parts[1],
      version: version,
      text: text,
    );
  }

  static String _restorePadding(String encoded) {
    final int remainder = encoded.length % 4;
    if (remainder == 0) {
      return encoded;
    }
    return '$encoded${'=' * (4 - remainder)}';
  }
}

/// 已解析的二维码传输负载。
class DecodedQrTransferPayload {
  const DecodedQrTransferPayload({
    required this.type,
    required this.version,
    required this.text,
  });

  final String type;
  final int version;
  final String text;

  dynamic decodeJson() {
    return jsonDecode(text);
  }
}
