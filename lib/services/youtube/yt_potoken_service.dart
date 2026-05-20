// YT PoToken 生成服务 — 移植自 NewPipe (TeamNewPipe/NewPipe)
//
// 关键思路:
//   1. 用一个隐形 WebView 加载 assets/yt/po_token.html(NewPipe 原版)
//   2. 向 Google BotGuard 服务请求 challenge:`/api/jnn/v1/Create`
//   3. 把 challenge 数据塞进 WebView 跑 `runBotGuard()` 得到 botguardResponse
//   4. 用 botguardResponse 换 integrityToken:`/api/jnn/v1/GenerateIT`
//   5. 用 integrityToken + 标识符(visitorData / videoId)在 WebView 里 `obtainPoToken()`
//   6. 得到 Uint8Array → base64url → poToken 字符串
//
// 关键事实:
//   - integrityToken 通常有效期 ~6 小时,在该期内可重复 mint 任意标识符的 poToken
//   - cold-start poToken(用 visitorData mint)塞 player 请求 header,后续 stream 请求
//     也用 video-id 单独 mint 一次 poToken 拼 `&pot=` 到 stream URL

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class YtPoTokenException implements Exception {
  final String message;
  YtPoTokenException(this.message);
  @override
  String toString() => 'YtPoTokenException: $message';
}

class YtPoTokenService {
  static const _googleApiKey = 'AIzaSyDyT5W0Jh49F30Pqqtyfdf7pDLFKLJoAnw';
  static const _requestKey = 'O43z0dpjhgX20SCx4KAo';
  static const _ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  HeadlessInAppWebView? _webView;
  InAppWebViewController? _ctr;
  DateTime? _expirationInstant;
  Completer<void>? _initCompleter;

  /// 单例 — 因为 BotGuard integrityToken 有效期 ~6 小时,可复用
  static YtPoTokenService? _instance;
  static YtPoTokenService get instance => _instance ??= YtPoTokenService._();
  YtPoTokenService._();

  bool get isExpired {
    final e = _expirationInstant;
    return e == null || DateTime.now().isAfter(e);
  }

  /// 初始化:加载 HTML → 拿 BotGuard challenge → 执行 → 拿 integrityToken
  /// 已初始化且未过期则直接返回。
  Future<void> initialize() async {
    if (!isExpired && _ctr != null) return;
    if (_initCompleter != null) return _initCompleter!.future;
    final c = _initCompleter = Completer<void>();
    try {
      await _doInit();
      c.complete();
    } catch (e) {
      c.completeError(e);
      _initCompleter = null;
      rethrow;
    }
  }

  Future<void> _doInit() async {
    // 关闭之前的 WebView
    await _webView?.dispose();
    _webView = null;
    _ctr = null;

    // 1. 拉 BotGuard challenge
    final rawChallenge = await _postBotGuardService(
      'https://www.youtube.com/api/jnn/v1/Create',
      '[ "$_requestKey" ]',
    );
    final challengeJson = _parseChallengeData(rawChallenge);

    // 2. 启动 headless WebView
    final loaded = Completer<void>();
    _webView = HeadlessInAppWebView(
      initialSettings: InAppWebViewSettings(
        userAgent: _ua,
        javaScriptEnabled: true,
      ),
      onWebViewCreated: (c) {
        _ctr = c;
      },
      onLoadStop: (controller, uri) {
        if (!loaded.isCompleted) loaded.complete();
      },
      onConsoleMessage: (_, m) {
        // ignore: avoid_print
        print('[PoToken WebView console] ${m.message}');
      },
    );
    await _webView!.run();
    // 加载 assets html
    await _ctr!.loadFile(assetFilePath: 'assets/yt/po_token.html');
    await loaded.future.timeout(const Duration(seconds: 10));

    // 3. 在 WebView 里跑 runBotGuard 拿 botguardResponse
    // 用 callAsyncJavaScript 才支持 Promise 返回
    // 超时保护:BotGuard VM 跑太慢(>20s) 时直接放弃,触发上层 fallback
    final CallAsyncJavaScriptResult? botguardCall;
    try {
      botguardCall = await _ctr!.callAsyncJavaScript(functionBody: '''
        try {
          const data = $challengeJson;
          const result = await runBotGuard(data);
          this.webPoSignalOutput = result.webPoSignalOutput;
          return result.botguardResponse;
        } catch (e) {
          return "__ERR__" + (e && e.message ? e.message : e);
        }
      ''').timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw YtPoTokenException('runBotGuard timeout (>20s)');
    }
    if (botguardCall == null) {
      throw YtPoTokenException('callAsyncJavaScript returned null (channel?)');
    }
    if (botguardCall.error != null) {
      throw YtPoTokenException('runBotGuard JS exception: ${botguardCall.error}');
    }
    final botguardResponseRaw = botguardCall.value;
    if (botguardResponseRaw == null) {
      throw YtPoTokenException('runBotGuard returned null value');
    }
    final botguardResponse = botguardResponseRaw.toString();
    if (botguardResponse.startsWith('__ERR__')) {
      throw YtPoTokenException(
          'runBotGuard JS error: ${botguardResponse.substring(7)}');
    }

    // 4. 拿 integrityToken
    final rawIT = await _postBotGuardService(
      'https://www.youtube.com/api/jnn/v1/GenerateIT',
      '[ "$_requestKey", ${jsonEncode(botguardResponse)} ]',
    );
    final parsedIT = _parseIntegrityTokenData(rawIT);
    final u8IntegrityToken = parsedIT.$1; // JS Uint8Array literal
    final expiresSec = parsedIT.$2;
    _expirationInstant =
        DateTime.now().add(Duration(seconds: expiresSec - 600));

    // 5. 把 integrityToken 挂到 WebView 上(后续 mint 复用)
    await _ctr!.evaluateJavascript(source: '''
      this.integrityToken = $u8IntegrityToken;
    ''');
  }

  /// 给指定标识符 mint poToken (string).
  /// identifier 通常是 video-id 或 visitor-data 字符串。
  Future<String> generatePoToken(String identifier) async {
    await initialize();
    final ctr = _ctr;
    if (ctr == null) throw YtPoTokenException('WebView not initialized');

    final u8Identifier = _stringToU8(identifier);
    final CallAsyncJavaScriptResult? call;
    try {
      call = await ctr.callAsyncJavaScript(functionBody: '''
        try {
          const u8Identifier = $u8Identifier;
          const poTokenU8 = obtainPoToken(this.webPoSignalOutput, this.integrityToken, u8Identifier);
          let s = "";
          for (let i = 0; i < poTokenU8.length; i++) {
            if (i !== 0) s += ",";
            s += poTokenU8[i];
          }
          return s;
        } catch (e) {
          return "__ERR__" + (e && e.message ? e.message : e);
        }
      ''').timeout(const Duration(seconds: 10));
    } on TimeoutException {
      throw YtPoTokenException('obtainPoToken timeout (>10s)');
    }
    if (call == null) throw YtPoTokenException('obtainPoToken channel null');
    if (call.error != null) {
      throw YtPoTokenException('obtainPoToken JS exception: ${call.error}');
    }
    final result = call.value;
    if (result == null) {
      throw YtPoTokenException('obtainPoToken returned null value');
    }
    final s = result.toString();
    if (s.startsWith('__ERR__')) {
      throw YtPoTokenException(
          'obtainPoToken JS error: ${s.substring(7)}');
    }
    return _u8ToBase64Url(s);
  }

  Future<void> close() async {
    await _webView?.dispose();
    _webView = null;
    _ctr = null;
    _expirationInstant = null;
    _initCompleter = null;
  }

  // ─────── BotGuard 服务请求 ───────
  static final _dio = Dio(BaseOptions(
    headers: {
      'User-Agent': _ua,
      'Accept': 'application/json',
      'Content-Type': 'application/json+protobuf',
      'x-goog-api-key': _googleApiKey,
      'x-user-agent': 'grpc-web-javascript/0.1',
    },
    responseType: ResponseType.plain,
    receiveTimeout: const Duration(seconds: 15),
  ));

  Future<String> _postBotGuardService(String url, String body) async {
    final resp = await _dio.post<String>(url, data: body);
    if (resp.statusCode != 200) {
      throw YtPoTokenException(
          'BotGuard $url failed: HTTP ${resp.statusCode} body=${resp.data}');
    }
    return resp.data ?? '';
  }

  // ─────── JS Util(移植自 NewPipe JavaScriptUtil.kt)───────

  /// 解析 BotGuard challenge,返回可嵌 JS 的 JSON 对象字面量(字符串)
  static String _parseChallengeData(String raw) {
    final scrambled = jsonDecode(raw) as List;
    List challenge;
    if (scrambled.length > 1 && scrambled[1] is String) {
      // descramble: base64 解码 + 每字节加 97
      final desc = _descramble(scrambled[1] as String);
      challenge = jsonDecode(desc) as List;
    } else {
      challenge = scrambled[0] as List;
    }
    final messageId = challenge[0] as String?;
    final interpreterHash = challenge[3] as String?;
    final program = challenge[4] as String?;
    final globalName = challenge[5] as String?;
    final clientExperimentsStateBlob =
        challenge.length > 7 ? challenge[7] as String? : null;

    String? safeScript;
    String? trustedResourceUrl;
    if (challenge.length > 1 && challenge[1] is List) {
      for (final x in challenge[1] as List) {
        if (x is String) {
          safeScript = x;
          break;
        }
      }
    }
    if (challenge.length > 2 && challenge[2] is List) {
      for (final x in challenge[2] as List) {
        if (x is String) {
          trustedResourceUrl = x;
          break;
        }
      }
    }

    return jsonEncode({
      'messageId': messageId,
      'interpreterJavascript': {
        'privateDoNotAccessOrElseSafeScriptWrappedValue': safeScript,
        'privateDoNotAccessOrElseTrustedResourceUrlWrappedValue':
            trustedResourceUrl,
      },
      'interpreterHash': interpreterHash,
      'program': program,
      'globalName': globalName,
      'clientExperimentsStateBlob': clientExperimentsStateBlob,
    });
  }

  /// 解析 GenerateIT 响应,返回 (jsUint8ArrayLiteral, expirationSeconds)
  static (String, int) _parseIntegrityTokenData(String raw) {
    final arr = jsonDecode(raw) as List;
    final tokenBase64 = arr[0] as String;
    final expiresSec = (arr[1] as num).toInt();
    final bytes = _base64ToBytes(tokenBase64);
    return (_newUint8Array(bytes), expiresSec);
  }

  static String _stringToU8(String s) => _newUint8Array(utf8.encode(s));

  static String _newUint8Array(List<int> contents) {
    final buf = StringBuffer('new Uint8Array([');
    for (var i = 0; i < contents.length; i++) {
      if (i != 0) buf.write(',');
      // 转无符号 byte 字符串
      buf.write(contents[i] & 0xff);
    }
    buf.write('])');
    return buf.toString();
  }

  /// 把 "97,98,99" 格式(JS Uint8Array.toString())转为 base64url poToken
  static String _u8ToBase64Url(String csv) {
    final parts = csv.split(',');
    final bytes = Uint8List(parts.length);
    for (var i = 0; i < parts.length; i++) {
      // 用 unsigned byte 解读(JS Uint8Array 元素 0..255)
      bytes[i] = int.parse(parts[i]) & 0xff;
    }
    var b64 = base64Encode(bytes);
    // base64 → base64url(YT poToken 用)
    b64 = b64.replaceAll('+', '-').replaceAll('/', '_');
    return b64;
  }

  /// 反向 scramble:base64 解码 + 每字节 +97 后解码 UTF-8
  static String _descramble(String s) {
    final raw = _base64ToBytes(s);
    final added = Uint8List.fromList(raw.map((b) => (b + 97) & 0xff).toList());
    return utf8.decode(added);
  }

  /// YT 用的特殊 base64(`-` `_` `.` 替代 `+` `/` `=`)
  static Uint8List _base64ToBytes(String s) {
    final norm = s.replaceAll('-', '+').replaceAll('_', '/').replaceAll('.', '=');
    return base64Decode(norm);
  }
}
