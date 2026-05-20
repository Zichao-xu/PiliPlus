// YouTube 登录状态管理
// 走 WebView 弹 Google 登录,拿到 SAPISID / SID 等 cookies 后:
// - 存到 GStorage.localCache 'yt_auth' key
// - InnerTube 请求时加 Authorization: SAPISIDHASH <hash> + Cookie header
// SAPISIDHASH 算法: SHA1("${unix}_${SAPISID}_https://www.youtube.com") (Google 内部约定)

import 'dart:convert';

import 'package:PiliPlus/utils/storage.dart';
import 'package:crypto/crypto.dart' show sha1;

class YtAuthService {
  static const _kKey = 'yt_auth_cookies';
  static const _kUserName = 'yt_auth_user_name';
  static const _kAvatarUrl = 'yt_auth_avatar_url';
  static const _kChannelId = 'yt_auth_channel_id';

  /// 当前已登录账号的 cookies 映射(name → value)。未登录返回 null。
  static Map<String, String>? get cookies {
    final raw = GStorage.localCache.get(_kKey);
    if (raw is String && raw.isNotEmpty) {
      try {
        return Map<String, String>.from(jsonDecode(raw) as Map);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  static bool get isLoggedIn {
    final c = cookies;
    return c != null && (c['SAPISID'] != null || c['__Secure-3PAPISID'] != null);
  }

  static String? get userName => GStorage.localCache.get(_kUserName) as String?;
  static String? get avatarUrl =>
      GStorage.localCache.get(_kAvatarUrl) as String?;
  static String? get channelId =>
      GStorage.localCache.get(_kChannelId) as String?;

  static Future<void> saveCookies(Map<String, String> map) async {
    // 只保留登录核心 cookies
    final keep = <String>{
      'SID', 'HSID', 'SSID', 'APISID', 'SAPISID',
      'LOGIN_INFO',
      '__Secure-1PSID', '__Secure-3PSID',
      '__Secure-1PAPISID', '__Secure-3PAPISID',
      '__Secure-1PSIDTS', '__Secure-3PSIDTS',
      '__Secure-1PSIDCC', '__Secure-3PSIDCC',
      'YSC', 'VISITOR_INFO1_LIVE', 'PREF',
    };
    final filtered = <String, String>{
      for (final e in map.entries)
        if (keep.contains(e.key)) e.key: e.value,
    };
    await GStorage.localCache.put(_kKey, jsonEncode(filtered));
  }

  static Future<void> saveUserInfo({
    String? name,
    String? avatarUrl,
    String? channelId,
  }) async {
    await Future.wait([
      if (name != null) GStorage.localCache.put(_kUserName, name),
      if (avatarUrl != null) GStorage.localCache.put(_kAvatarUrl, avatarUrl),
      if (channelId != null) GStorage.localCache.put(_kChannelId, channelId),
    ]);
  }

  static Future<void> logout() async {
    await Future.wait([
      GStorage.localCache.delete(_kKey),
      GStorage.localCache.delete(_kUserName),
      GStorage.localCache.delete(_kAvatarUrl),
      GStorage.localCache.delete(_kChannelId),
    ]);
  }

  /// 给 InnerTube 私享接口请求注入的 header。未登录返回 null。
  static Map<String, String>? buildAuthHeaders({
    String origin = 'https://www.youtube.com',
  }) {
    final c = cookies;
    if (c == null) return null;
    final sapisid = c['SAPISID'] ?? c['__Secure-3PAPISID'] ?? c['__Secure-1PAPISID'];
    if (sapisid == null || sapisid.isEmpty) return null;
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final hashInput = '${ts}_${sapisid}_$origin';
    final hash = sha1.convert(hashInput.codeUnits).toString();
    final cookieStr = c.entries.map((e) => '${e.key}=${e.value}').join('; ');
    return {
      'Authorization': 'SAPISIDHASH ${ts}_$hash',
      'Cookie': cookieStr,
      'X-Origin': origin,
      'Origin': origin,
      'X-Goog-AuthUser': '0',
    };
  }
}
