import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// 福州理工学院教务系统网页自动化脚本。
///
/// 使用固定 DOM 选择器（#yhm/#mm/#yzm/#yzmPic/#dl），
/// 并通过 [callAsyncJavascript] 异步等待元素出现，避免 DOM 未就绪导致填充失败。
class FitLoginWebAutomation {
  const FitLoginWebAutomation._();

  // ---------------------------------------------------------------------------
  // JS 辅助片段（在多个方法中复用）
  // ---------------------------------------------------------------------------

  /// 等待指定 ID 的 DOM 元素出现，超时返回 null。
  static const String _waitForElementJs = '''
    const _waitFor = (id, timeoutMs) => new Promise(resolve => {
      const start = Date.now();
      const poll = () => {
        const el = document.getElementById(id);
        if (el) return resolve(el);
        if (Date.now() - start > timeoutMs) return resolve(null);
        setTimeout(poll, 100);
      };
      poll();
    });
  ''';

  /// 设置 input 元素的值，并派发 input / change 事件。
  ///
  /// 使用原生 setter 绕过 React / Vue 等框架的 value 代理，
  /// 确保框架能感知到值变更。
  static const String _setValueJs = '''
    const _setValue = (el, val) => {
      if (!el) return false;
      el.focus();
      const nativeSetter = Object.getOwnPropertyDescriptor(
        window.HTMLInputElement.prototype, 'value'
      )?.set;
      if (nativeSetter) {
        nativeSetter.call(el, val);
      } else {
        el.value = val;
      }
      el.dispatchEvent(new Event('input',  { bubbles: true }));
      el.dispatchEvent(new Event('change', { bubbles: true }));
      el.blur();
      return true;
    };
  ''';

  // ---------------------------------------------------------------------------
  // 公开方法
  // ---------------------------------------------------------------------------

  /// 填入用户名与密码。
  ///
  /// 内部会等待 `#yhm` 和 `#mm` 元素出现（最多 3 秒），避免 DOM 未渲染时失败。
  /// 返回填充状态 Map，包含 `yhmFound`、`mmFound`、`yhmFilled`、`mmFilled`。
  static Future<Map<String, dynamic>> fillCredentials({
    required InAppWebViewController controller,
    required String username,
    required String password,
  }) async {
    debugPrint('[FIT 自动填充] 开始填入账号密码...');

    final CallAsyncJavaScriptResult? result = await controller
        .callAsyncJavaScript(
          functionBody:
              '''
        $_waitForElementJs
        $_setValueJs

        const usernameInput = await _waitFor('yhm', 3000);
        const passwordInput = await _waitFor('mm',  3000);

        const yhmOk = _setValue(usernameInput, username);

        const _setPasswordSecure = (el, val) => {
          if (!el) {
            return { filled: false, masked: false };
          }

          try {
            // 强制密码框为掩码模式，避免明文显示。
            el.setAttribute('type', 'password');
            el.autocomplete = 'off';
            el.style.webkitTextSecurity = 'disc';
          } catch (_) {}

          const nativeSetter = Object.getOwnPropertyDescriptor(
            window.HTMLInputElement.prototype, 'value'
          )?.set;
          if (nativeSetter) {
            nativeSetter.call(el, val);
          } else {
            el.value = val;
          }

          el.dispatchEvent(new Event('input',  { bubbles: true }));
          el.dispatchEvent(new Event('change', { bubbles: true }));

          // 某些页面脚本可能把 type 改回 text，这里再次兜底恢复为 password。
          try {
            if ((el.type || '').toLowerCase() !== 'password') {
              el.setAttribute('type', 'password');
            }
          } catch (_) {}

          return {
            filled: true,
            masked: (el.type || '').toLowerCase() === 'password'
          };
        };

        const mmResult = _setPasswordSecure(passwordInput, password);

        return {
          yhmFound:  !!usernameInput,
          mmFound:   !!passwordInput,
          yhmFilled: yhmOk,
          mmFilled:  mmResult.filled,
          mmMasked:  mmResult.masked
        };
      ''',
          arguments: <String, dynamic>{
            'username': username,
            'password': password,
          },
        );

    final Map<String, dynamic> status = _extractMap(result);
    debugPrint('[FIT 自动填充] 填充结果: $status, 错误: ${result?.error}');
    return status;
  }

  /// 从验证码图片（#yzmPic）提取 DataURL，供 OCR 识别。
  ///
  /// 会等待图片元素加载完成（`complete` 且有实际尺寸），最多 5 秒。
  static Future<String?> extractCaptchaDataUrl(
    InAppWebViewController controller,
  ) async {
    debugPrint('[FIT 验证码] 开始提取验证码图片...');

    final CallAsyncJavaScriptResult? result = await controller
        .callAsyncJavaScript(
          functionBody: '''
        // 等待图片元素加载完成（complete 且有实际尺寸）
        const waitForImage = (id, timeoutMs) => new Promise(resolve => {
          const start = Date.now();
          const poll = () => {
            const el = document.getElementById(id);
            if (el && el.complete && el.naturalWidth > 0 && el.naturalHeight > 0) {
              return resolve(el);
            }
            if (Date.now() - start > timeoutMs) return resolve(el || null);
            setTimeout(poll, 200);
          };
          poll();
        });

        const captchaImg = await waitForImage('yzmPic', 5000);
        if (!captchaImg) {
          return { found: false, reason: 'element #yzmPic not found' };
        }

        if (!captchaImg.complete || captchaImg.naturalWidth <= 0) {
          return {
            found: true,
            loaded: false,
            reason: 'image not fully loaded',
            src: captchaImg.src || ''
          };
        }

        // src 本身已经是 data:image 格式则直接返回
        if (captchaImg.src && captchaImg.src.startsWith('data:image')) {
          return { found: true, loaded: true, dataUrl: captchaImg.src };
        }

        try {
          const canvas  = document.createElement('canvas');
          canvas.width  = captchaImg.naturalWidth;
          canvas.height = captchaImg.naturalHeight;
          const ctx = canvas.getContext('2d');
          if (!ctx) {
            return { found: true, loaded: true, reason: 'canvas context null' };
          }
          ctx.drawImage(captchaImg, 0, 0);
          const dataUrl = canvas.toDataURL('image/png');
          return {
            found: true,
            loaded: true,
            dataUrl: dataUrl,
            width: captchaImg.naturalWidth,
            height: captchaImg.naturalHeight
          };
        } catch (e) {
          return {
            found: true,
            loaded: true,
            reason: 'canvas toDataURL error: ' + e.message,
            src: captchaImg.src || ''
          };
        }
      ''',
        );

    final Map<String, dynamic> status = _extractMap(result);
    final String dataUrl = (status['dataUrl'] as String?) ?? '';
    debugPrint(
      '[FIT 验证码] 提取结果: found=${status['found']}, loaded=${status['loaded']}, '
      'dataUrlLen=${dataUrl.length}, reason=${status['reason']}, '
      'error=${result?.error}',
    );

    return dataUrl.isNotEmpty ? dataUrl : null;
  }

  /// 填写验证码并触发登录按钮点击。
  static Future<bool> fillCaptchaAndSubmit({
    required InAppWebViewController controller,
    required String captchaCode,
  }) async {
    debugPrint('[FIT 提交] 开始填入验证码($captchaCode)并提交...');

    final CallAsyncJavaScriptResult? result = await controller
        .callAsyncJavaScript(
          functionBody:
              '''
        $_setValueJs

        const captchaInput = document.getElementById('yzm');
        const loginButton  = document.getElementById('dl');

        const yzmOk = _setValue(captchaInput, captchaCode);

        if (loginButton) {
          loginButton.click();
          return { submitted: true, method: 'button click', yzmFilled: yzmOk };
        }

        const form = captchaInput?.form || document.querySelector('form');
        if (form) {
          form.submit();
          return { submitted: true, method: 'form submit', yzmFilled: yzmOk };
        }

        return {
          submitted: false,
          yzmFilled: yzmOk,
          reason: 'no button or form found'
        };
      ''',
          arguments: <String, dynamic>{'captchaCode': captchaCode},
        );

    final Map<String, dynamic> status = _extractMap(result);
    debugPrint('[FIT 提交] 提交结果: $status, 错误: ${result?.error}');
    return status['submitted'] == true;
  }

  // ---------------------------------------------------------------------------
  // 内部工具
  // ---------------------------------------------------------------------------

  /// 从 [CallAsyncJavaScriptResult] 中安全提取 Map。
  static Map<String, dynamic> _extractMap(CallAsyncJavaScriptResult? result) {
    final dynamic value = result?.value;
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return <String, dynamic>{};
  }
}
