// 免 key 翻译服务(MyMemory anonymous)
//
// 选 MyMemory(api.mymemory.translated.net) 因为:
// - 完全 anonymous,无需注册/API key
// - 单 IP 1000 字/天 免费,个人用 YT 标题/简介/Tag/评论 够用
// - 标准 HTTP GET,直接 dio 调,无反爬
// - 文档:https://mymemory.translated.net/doc/spec.php
//
// 退化:超日额度 → server 返回 quotaFinished,我们 throw 文字提示。
// 用户在 [SettingBoxKey.ytTranslateTargetLang] 配 DeepL 风格代码(ZH-HANS / EN / JA...),
// 这里做映射到 MyMemory 的 ISO 标签(zh-CN / en / ja)。

import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:dio/dio.dart';

class YtTranslateService {
  YtTranslateService._();
  static final instance = YtTranslateService._();

  final Dio _dio = Dio(BaseOptions(
    receiveTimeout: const Duration(seconds: 12),
    sendTimeout: const Duration(seconds: 10),
  ));

  final Map<String, String> _cache = {};

  String get _defaultTargetLang =>
      GStorage.setting.get(SettingBoxKey.ytTranslateTargetLang,
              defaultValue: 'ZH-HANS') as String;

  /// MyMemory 无需 key,永远可用
  bool get isConfigured => true;

  /// 启发式源语言识别(MyMemory 不接受 auto)
  /// - 全 ASCII → en
  /// - 含日文假名(hiragana/katakana) → ja
  /// - 含韩文 Hangul → ko
  /// - 含 CJK 汉字 → zh-CN
  /// - 其他 → en(兜底)
  static String detectSourceLang(String text) {
    var hasAscii = false;
    var hasJaKana = false;
    var hasHangul = false;
    var hasCjk = false;
    for (final r in text.runes) {
      // ASCII printable
      if (r >= 0x20 && r < 0x7F) hasAscii = true;
      // 日文 hiragana 3040-309F  katakana 30A0-30FF
      else if ((r >= 0x3040 && r <= 0x30FF) ||
          (r >= 0xFF66 && r <= 0xFF9F)) {
        hasJaKana = true;
      }
      // 韩文 Hangul AC00-D7AF
      else if (r >= 0xAC00 && r <= 0xD7AF) {
        hasHangul = true;
      }
      // CJK 汉字 4E00-9FFF / 3400-4DBF 扩展A
      else if ((r >= 0x4E00 && r <= 0x9FFF) ||
          (r >= 0x3400 && r <= 0x4DBF)) {
        hasCjk = true;
      }
    }
    if (hasJaKana) return 'ja';
    if (hasHangul) return 'ko';
    if (hasCjk) return 'zh-CN';
    if (hasAscii) return 'en';
    return 'en';
  }

  /// DeepL 风格 → MyMemory ISO 代码
  static String _toMyMemoryLang(String deeplCode) {
    switch (deeplCode.toUpperCase()) {
      case 'ZH-HANS':
      case 'ZH':
        return 'zh-CN';
      case 'ZH-HANT':
        return 'zh-TW';
      case 'EN':
      case 'EN-US':
        return 'en-US';
      case 'EN-GB':
        return 'en-GB';
      case 'PT-BR':
        return 'pt-BR';
      case 'PT-PT':
        return 'pt-PT';
      default:
        // 'JA' -> 'ja', 'KO' -> 'ko' 等通用 case
        return deeplCode.toLowerCase();
    }
  }

  /// MyMemory 单次 GET 文本上限。超出会 414 URI Too Long。
  /// 实测留余量到 400 字符(URL 编码后中文 ×3 倍,400 中文 ≈ 1200 字节 → URL 总长 ~1.5KB,稳)
  static const _maxChunkChars = 400;

  /// 翻译单段。长文本自动按句号 / 换行切片后逐段翻译再拼回。失败 throw。
  Future<String> translate(String text, {String? targetLang}) async {
    if (text.trim().isEmpty) return text;
    final target = _toMyMemoryLang(targetLang ?? _defaultTargetLang);
    final cacheKey = '$target|$text';
    final hit = _cache[cacheKey];
    if (hit != null) return hit;

    final src = detectSourceLang(text);
    if (src.split('-').first == target.split('-').first) {
      _cache[cacheKey] = text;
      return text;
    }

    // 长文本切片:按句号 / 换行,每段 ≤ _maxChunkChars
    final chunks = _splitForTranslate(text);
    final out = StringBuffer();
    for (final c in chunks) {
      out.write(await _translateChunk(c, src, target));
    }
    final translated = out.toString();
    _cache[cacheKey] = translated;
    return translated;
  }

  Future<String> _translateChunk(
      String text, String src, String target) async {
    if (text.isEmpty) return text;
    final resp = await _dio.get<Map<String, dynamic>>(
      'https://api.mymemory.translated.net/get',
      queryParameters: {
        'q': text,
        'langpair': '$src|$target',
      },
      options: Options(responseType: ResponseType.json),
    );
    if (resp.statusCode != 200 || resp.data == null) {
      throw Exception('MyMemory HTTP ${resp.statusCode}');
    }
    final data = resp.data!;
    final status = data['responseStatus'];
    if (status != 200 && status != '200') {
      final details = data['responseDetails'];
      throw Exception('MyMemory: $details');
    }
    return (data['responseData']?['translatedText'] as String?) ?? text;
  }

  /// 按 句末标点 / 换行 切,每段 ≤ [_maxChunkChars]。单句过长再硬切。
  static List<String> _splitForTranslate(String text) {
    if (text.length <= _maxChunkChars) return [text];
    final out = <String>[];
    final buf = StringBuffer();
    // 句末标点(中英日韩通用)+ 换行 切分点
    final breakers = RegExp(r'[\.!?。!?\n]');
    var i = 0;
    while (i < text.length) {
      final ch = text[i];
      buf.write(ch);
      final isBreak = breakers.hasMatch(ch);
      if (isBreak && buf.length >= _maxChunkChars ~/ 2) {
        out.add(buf.toString());
        buf.clear();
      } else if (buf.length >= _maxChunkChars) {
        // 没碰到句末就到上限 → 硬切
        out.add(buf.toString());
        buf.clear();
      }
      i++;
    }
    if (buf.isNotEmpty) out.add(buf.toString());
    return out;
  }

  /// 批量:MyMemory 单请求只支持单段,这里 loop 调
  Future<List<String>> translateMany(List<String> texts,
      {String? targetLang}) async {
    if (texts.isEmpty) return const [];
    final out = <String>[];
    for (final t in texts) {
      try {
        out.add(await translate(t, targetLang: targetLang));
      } catch (e) {
        // 单段失败保留原文,不挂整批
        out.add(t);
      }
    }
    return out;
  }
}
