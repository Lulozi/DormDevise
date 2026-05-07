import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// 福州理工学院验证码 OCR（百度翻译图片翻译接口）。
///
/// 使用百度翻译开放平台的「图片翻译」API，免费版 QPS 限制比文字识别宽松。
/// 注册地址：https://fanyi-api.baidu.com/
///
/// 需要通过 dart-define 提供密钥：
/// - FIT_BAIDU_FANYI_APPID
/// - FIT_BAIDU_FANYI_SECRET
class FitChinaOcrService {
  static const String _appId = String.fromEnvironment('FIT_BAIDU_FANYI_APPID');
  static const String _secret = String.fromEnvironment(
    'FIT_BAIDU_FANYI_SECRET',
  );

  /// 百度翻译图片翻译 API 地址。
  static const String _apiEndpoint =
      'https://fanyi-api.baidu.com/api/trans/sdk/picture';

  final Random _random = Random();

  /// 识别 DataURL 格式验证码图片，返回清洗后的纯字母/数字文本。
  Future<String?> recognizeCaptchaFromDataUrl(String dataUrl) async {
    final Uint8List? imageBytes = _decodeDataUrlToBytes(dataUrl);
    if (imageBytes == null || imageBytes.isEmpty) {
      debugPrint('[FIT OCR] 图片数据为空，无法识别');
      return null;
    }

    if (_appId.isEmpty || _secret.isEmpty) {
      debugPrint('[FIT OCR] 未配置百度翻译密钥，跳过自动识别');
      debugPrint(
        '[FIT OCR] 请通过 --dart-define=FIT_BAIDU_FANYI_APPID=xxx '
        '--dart-define=FIT_BAIDU_FANYI_SECRET=yyy 传入',
      );
      return null;
    }

    // 打印部分密钥用于调试（仅显示前 6 字符）。
    final String maskedAppId = _appId.length > 6
        ? '${_appId.substring(0, 6)}...'
        : _appId;
    debugPrint('[FIT OCR] 正在调用百度翻译图片 API, appId=$maskedAppId');

    // 百度翻译免费版 QPS 为 1，遇到限流时自动重试。
    const int maxRetries = 3;
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final String? result = await _callPictureApi(imageBytes);
        if (result != null) return result;

        // result 为 null 可能是限流，等待后重试
        if (attempt < maxRetries) {
          final int delaySeconds = attempt * 2;
          debugPrint(
            '[FIT OCR] 第 $attempt 次请求未获得结果，等待 ${delaySeconds}s 后重试...',
          );
          await Future<void>.delayed(Duration(seconds: delaySeconds));
        }
      } catch (error) {
        debugPrint('[FIT OCR] 识别异常(第 $attempt 次): $error');
        if (attempt == maxRetries) return null;
        await Future<void>.delayed(Duration(seconds: attempt * 2));
      }
    }
    return null;
  }

  /// 调用百度翻译图片翻译 API。
  Future<String?> _callPictureApi(Uint8List imageBytes) async {
    final String salt = _random.nextInt(1000000000).toString();

    // cuid / mac 为必填字段，可填固定值。
    const String cuid = 'dormdevise';
    const String mac = '00:00:00:00:00:00';

    // 签名规则: md5(appid + md5(image) + salt + cuid + mac + secretKey)
    final String imageMd5 = md5.convert(imageBytes).toString();
    final String signRaw = '$_appId$imageMd5$salt$cuid$mac$_secret';
    final String sign = md5.convert(utf8.encode(signRaw)).toString();

    debugPrint(
      '[FIT OCR] 签名参数: appid=$_appId, salt=$salt, '
      'imageMd5=$imageMd5, signRaw长度=${signRaw.length}',
    );

    // 构建 multipart 请求
    final http.MultipartRequest request = http.MultipartRequest(
      'POST',
      Uri.parse(_apiEndpoint),
    );
    request.fields['from'] = 'en';
    request.fields['to'] = 'zh';
    request.fields['appid'] = _appId;
    request.fields['salt'] = salt;
    request.fields['sign'] = sign;
    request.fields['cuid'] = cuid;
    request.fields['mac'] = mac;
    request.files.add(
      http.MultipartFile.fromBytes(
        'image',
        imageBytes,
        filename: 'captcha.png',
      ),
    );

    final http.StreamedResponse streamedResponse = await request.send();
    final String responseBody = await streamedResponse.stream.bytesToString();

    debugPrint('[FIT OCR] 百度翻译响应: $responseBody');

    if (streamedResponse.statusCode < 200 ||
        streamedResponse.statusCode >= 300) {
      debugPrint('[FIT OCR] HTTP 请求失败: status=${streamedResponse.statusCode}');
      return null;
    }

    final Map<String, dynamic> json =
        jsonDecode(responseBody) as Map<String, dynamic>;

    // 检查错误码
    final String? errorCode = json['error_code']?.toString();
    if (errorCode != null && errorCode != '0' && errorCode != 'null') {
      final String? errorMsg = json['error_msg']?.toString();
      debugPrint('[FIT OCR] 百度翻译错误: code=$errorCode, msg=$errorMsg');
      return null;
    }

    // 提取原文文本
    // 响应结构: { "data": { "sumSrc": "识别到的原始文本", "sumDst": "翻译结果", ... } }
    final Map<String, dynamic>? data = json['data'] as Map<String, dynamic>?;
    if (data == null) {
      debugPrint('[FIT OCR] 响应中无 data 字段');
      return null;
    }

    final String rawText = (data['sumSrc'] as String?)?.trim() ?? '';
    if (rawText.isEmpty) {
      debugPrint('[FIT OCR] sumSrc 为空，未识别到文本');
      return null;
    }

    final String normalizedCaptcha = _normalizeCaptcha(rawText);
    debugPrint('[FIT OCR] 识别原文: $rawText');
    debugPrint('[FIT OCR] 清洗结果: $normalizedCaptcha');

    return normalizedCaptcha.isEmpty ? null : normalizedCaptcha;
  }

  /// 清洗验证码文本：只保留大写字母和数字，最多 6 位。
  String _normalizeCaptcha(String rawText) {
    final String result = rawText.toUpperCase().replaceAll(
      RegExp(r'[^A-Z0-9]'),
      '',
    );

    if (result.length <= 6) {
      return result;
    }
    return result.substring(0, 6);
  }

  /// 从 DataURL 解码为二进制字节。
  Uint8List? _decodeDataUrlToBytes(String dataUrl) {
    if (dataUrl.isEmpty) return null;
    final int commaIndex = dataUrl.indexOf(',');
    if (commaIndex < 0) return null;
    try {
      return base64Decode(dataUrl.substring(commaIndex + 1));
    } catch (_) {
      debugPrint('[FIT OCR] base64 解码失败');
      return null;
    }
  }
}
