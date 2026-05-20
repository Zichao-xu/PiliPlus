// YT 登录页:cookie 粘贴方式登录(避开 Google 对嵌入 WebView 的拦截)。
//
// 用户步骤:
//   1. 在 Safari/Chrome 桌面端打开 youtube.com 并登录
//   2. 打开 DevTools → Application → Cookies → www.youtube.com
//   3. 复制 SAPISID / __Secure-1PSID / LOGIN_INFO 等核心 cookie
//   4. 粘贴到本页 textarea(支持 `name=value;name=value` 或多行)
//   5. 点保存

import 'package:PiliPlus/utils/yt_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

class YtLoginPage extends StatefulWidget {
  const YtLoginPage({super.key});

  @override
  State<YtLoginPage> createState() => _YtLoginPageState();
}

class _YtLoginPageState extends State<YtLoginPage> {
  final _textCtr = TextEditingController();
  bool _loading = false;

  /// 必备 cookie 名(三选一,SAPISID 或 1PAPISID 或 3PAPISID 必有其一)
  static const _requiredAny = {
    'SAPISID',
    '__Secure-1PAPISID',
    '__Secure-3PAPISID',
  };

  /// 解析粘贴文本为 cookie map
  /// 支持格式:
  ///   - `name=value; name2=value2`(浏览器 Cookie header 风格)
  ///   - 每行一个 `name=value`
  ///   - DevTools "Copy as cURL" 出来的 `name\tvalue`
  Map<String, String> _parseCookies(String input) {
    final out = <String, String>{};
    if (input.trim().isEmpty) return out;
    // 把分号 / 换行 统一为分隔符
    final tokens = input.split(RegExp(r'[;\n\r]+'));
    for (final tk in tokens) {
      final t = tk.trim();
      if (t.isEmpty) continue;
      var eq = t.indexOf('=');
      if (eq < 0) eq = t.indexOf('\t');
      if (eq < 0) continue;
      final name = t.substring(0, eq).trim();
      final value = t.substring(eq + 1).trim();
      if (name.isEmpty || value.isEmpty) continue;
      out[name] = value;
    }
    return out;
  }

  Future<void> _submit() async {
    if (_loading) return;
    final raw = _textCtr.text;
    final map = _parseCookies(raw);
    final hasRequired = _requiredAny.any((k) => map[k] != null);
    if (!hasRequired) {
      SmartDialog.showToast(
        '至少需要 SAPISID / __Secure-1PAPISID / __Secure-3PAPISID 其中一个',
      );
      return;
    }
    setState(() => _loading = true);
    try {
      await YtAuthService.saveCookies(map);
      if (!mounted) return;
      SmartDialog.showToast('Cookie 已保存,YouTube 已登录');
      Get.back(result: true);
    } catch (e) {
      SmartDialog.showToast('保存失败:$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final t = data?.text;
    if (t == null || t.isEmpty) {
      SmartDialog.showToast('剪贴板为空');
      return;
    }
    _textCtr.text = t;
  }

  @override
  void dispose() {
    _textCtr.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('YouTube 登录(Cookie)'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('为什么这么麻烦',
                        style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    const Text(
                      'Google 不允许第三方 app 内嵌 WebView 登录,所以只能在桌面浏览器登录后,'
                      '把 cookie 粘贴回来。粘贴一次就行,App 会保存。',
                      style: TextStyle(height: 1.4),
                    ),
                    const SizedBox(height: 10),
                    Text('登录步骤',
                        style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    const Text(
                      '1. 桌面浏览器打开 youtube.com 并登录\n'
                      '2. 开发者工具 → Application → Cookies → www.youtube.com\n'
                      '3. 复制下面这几个 cookie 的 name=value:\n'
                      '   • SAPISID(必须)\n'
                      '   • __Secure-1PAPISID 或 __Secure-3PAPISID(必须有一个)\n'
                      '   • __Secure-1PSID / __Secure-3PSID(可选,可获得更全权限)\n'
                      '   • LOGIN_INFO / SID / HSID / SSID / APISID(可选)\n'
                      '4. 粘贴到下面文本框,点保存',
                      style: TextStyle(height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TextField(
                controller: _textCtr,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: InputDecoration(
                  hintText:
                      'SAPISID=xxx; __Secure-1PAPISID=xxx; __Secure-1PSID=xxx; ...',
                  border: const OutlineInputBorder(),
                  alignLabelWithHint: true,
                  contentPadding: const EdgeInsets.all(12),
                  fillColor: theme.colorScheme.surfaceContainerLow,
                  filled: true,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _loading ? null : _pasteFromClipboard,
                  icon: const Icon(Icons.content_paste),
                  label: const Text('从剪贴板粘贴'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('保存并登录'),
                ),
              ],
            ),
            if (YtAuthService.isLoggedIn) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _loading
                    ? null
                    : () async {
                        await YtAuthService.logout();
                        if (mounted) setState(() {});
                        SmartDialog.showToast('已注销');
                      },
                icon: const Icon(Icons.logout),
                label: Text(
                    '注销当前账号${YtAuthService.userName != null ? "(${YtAuthService.userName})" : ""}'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
