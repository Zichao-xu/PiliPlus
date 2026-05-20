// 自写 Innertube /player 调用 — 走 iOS client + poToken,绕过 cipher 解密
//
// 思路(参 NewPipeExtractor YoutubeStreamHelper.getIosPlayerResponse):
//   1. /youtubei/v1/visitor_id 拿 visitorData
//   2. mint cold-start poToken (绑 visitorData)
//   3. POST /youtubei/v1/player @ youtubei.googleapis.com  + IOS client + poToken
//   4. 解析 streamingData.adaptiveFormats → video/audio split URLs
//   5. 每个 stream URL 追加 `&pot=<contentPoToken>`(绑 videoId)
//
// 为啥用 IOS client:
//   - 不需要 signatureTimestamp(WEB 客户端必须有,要解析 player.js,工作量大)
//   - 直接返回原始 URL,不需要 cipher 解密
//   - 仍能拿到 1080p H.264 (mp4)
//   - 默认会返回 hlsManifestUrl 也行

import 'dart:convert';

import 'package:PiliPlus/services/youtube/yt_potoken_service.dart';
import 'package:PiliPlus/utils/yt_auth.dart';
import 'package:dio/dio.dart';

class YtIntFormat {
  final int itag;
  final String url;
  final String mimeType;
  final int bitrate;
  final String? qualityLabel;
  final int? width;
  final int? height;
  final int? fps;
  final String container;
  final String codec;
  final bool hasVideo;
  final bool hasAudio;
  final String? audioTrackId;
  final bool isDubbedAudio;

  YtIntFormat({
    required this.itag,
    required this.url,
    required this.mimeType,
    required this.bitrate,
    required this.qualityLabel,
    required this.width,
    required this.height,
    required this.fps,
    required this.container,
    required this.codec,
    required this.hasVideo,
    required this.hasAudio,
    required this.audioTrackId,
    required this.isDubbedAudio,
  });
}

class YtInnertubePlayerResponse {
  final List<YtIntFormat> formats;
  final String? hlsManifestUrl;
  final int? durationMs;
  final String visitorData;
  YtInnertubePlayerResponse({
    required this.formats,
    required this.hlsManifestUrl,
    required this.durationMs,
    required this.visitorData,
  });
}

/// 调 /player 时用的 Innertube client。
/// - [androidVr]:免登录主路径(yt-dlp 默认),REQUIRE_PO_TOKEN=True,SUPPORTS_COOKIES=False
/// - [mweb]:登录路径,SUPPORTS_COOKIES=True,GVS poToken
enum YtInnertubeClient { androidVr, mweb }

class YtInnertubePlayer {
  // === IOS client(已弃用 — server 不认 cookie auth on IOS UA)===
  // static const _iosClientVersion = '21.03.2';

  // === ANDROID_VR client(yt-dlp 默认免登录主路径,2026-Q1-Q2 仍 work but erratic)===
  // 参 yt-dlp `_INNERTUBE_CLIENTS['android_vr']`
  static const _avrClientVersion = '1.61.48';
  static const _avrDeviceModel = 'Quest 3';
  static const _avrOsVersion = '12L';
  static const _avrAndroidSdk = 32;
  static const _avrUa = 'com.google.android.apps.youtube.vr.oculus/'
      '$_avrClientVersion (Linux; U; Android $_avrOsVersion; en_US) gzip';

  // === MWEB client(登录路径,SUPPORTS_COOKIES=True)===
  static const _mwebClientVersion = '2.20260120.01.00';
  static const _mwebUa =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';

  // === WEB client(只用于 /visitor_id)===
  static const _webClientVersion = '2.20260120.01.00';
  static const _webUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  static const _youtubeiV1 = 'https://www.youtube.com/youtubei/v1';
  static const _youtubeiV1Gapis = 'https://youtubei.googleapis.com/youtubei/v1';

  static final _dio = Dio(BaseOptions(
    receiveTimeout: const Duration(seconds: 20),
    sendTimeout: const Duration(seconds: 15),
  ));

  static String? _cachedVisitorData;
  static DateTime? _visitorDataAt;

  /// 拿 visitorData(浏览器/客户端 ID)
  /// 缓存策略:**仅内存**(NewPipe 一样)。
  /// visitorData 必须与 BotGuard integrityToken 绑同一会话,持久化会导致 LOGIN_REQUIRED。
  static Future<String> fetchVisitorData() async {
    // 内存命中(同进程内复用)
    final cached = _cachedVisitorData;
    if (cached != null &&
        _visitorDataAt != null &&
        DateTime.now().difference(_visitorDataAt!).inHours < 6) {
      return cached;
    }
    // 用 WEB client 走 /visitor_id
    final body = {
      'context': {
        'client': {
          'clientName': 'WEB',
          'clientVersion': _webClientVersion,
          'hl': 'en',
          'gl': 'US',
        }
      }
    };
    final resp = await _dio.post<Map<String, dynamic>>(
      '$_youtubeiV1/visitor_id?prettyPrint=false',
      data: jsonEncode(body),
      options: Options(
        headers: {
          'User-Agent': _webUa,
          'Content-Type': 'application/json',
          'X-Youtube-Client-Name': '1',
          'X-Youtube-Client-Version': _webClientVersion,
          'Origin': 'https://www.youtube.com',
        },
        responseType: ResponseType.json,
      ),
    );
    if (resp.statusCode != 200 || resp.data == null) {
      throw Exception('visitor_id failed HTTP ${resp.statusCode}');
    }
    final vd = resp.data!['responseContext']?['visitorData'] as String?;
    if (vd == null || vd.isEmpty) {
      throw Exception('visitorData missing from /visitor_id response');
    }
    _cachedVisitorData = vd;
    _visitorDataAt = DateTime.now();
    return vd;
  }

  /// 调 /player 拿 streamingData。
  /// 默认 [YtInnertubeClient.androidVr] 走免登录路径。上层 [YtVideoService.fetchMuxedStreams]
  /// 会按热备链调:androidVr → mweb(登录态)→ yt_explode。
  static Future<YtInnertubePlayerResponse> fetchPlayer(
    String videoId, {
    YtInnertubeClient client = YtInnertubeClient.androidVr,
  }) {
    return _fetchPlayerOnce(videoId, client: client);
  }

  static Future<YtInnertubePlayerResponse> _fetchPlayerOnce(
    String videoId, {
    required YtInnertubeClient client,
  }) async {
    // 1. visitorData
    final visitorData = await fetchVisitorData();

    // 2/3. poToken
    // ANDROID_VR: REQUIRE_PO_TOKEN=True,Player + GVS 都要
    // MWEB:      GVS poToken 够,Player 不需要,带上也无害
    final streamingPoToken =
        await YtPoTokenService.instance.generatePoToken(visitorData);
    final playerPoToken =
        await YtPoTokenService.instance.generatePoToken(videoId);

    // build context.client + UA + auth-header strategy by client
    final Map<String, dynamic> clientCtx;
    final String ua;
    final bool injectCookie;
    switch (client) {
      case YtInnertubeClient.androidVr:
        clientCtx = {
          'clientName': 'ANDROID_VR',
          'clientVersion': _avrClientVersion,
          'deviceMake': 'Oculus',
          'deviceModel': _avrDeviceModel,
          'androidSdkVersion': _avrAndroidSdk,
          'osName': 'Android',
          'osVersion': _avrOsVersion,
          'hl': 'en',
          'gl': 'US',
          'visitorData': visitorData,
          'userAgent': _avrUa,
        };
        ua = _avrUa;
        injectCookie = false; // SUPPORTS_COOKIES=False
        break;
      case YtInnertubeClient.mweb:
        clientCtx = {
          'clientName': 'MWEB',
          'clientVersion': _mwebClientVersion,
          'platform': 'MOBILE',
          'deviceMake': 'Apple',
          'deviceModel': 'iPhone',
          'osName': 'iPhone',
          'osVersion': '17.0',
          'hl': 'en',
          'gl': 'US',
          'visitorData': visitorData,
          'userAgent': _mwebUa,
        };
        ua = _mwebUa;
        injectCookie = true; // SUPPORTS_COOKIES=True
        break;
    }

    final body = {
      'videoId': videoId,
      'cpn': _generateCpn(),
      'context': {
        'client': clientCtx,
        'user': {'lockedSafetyMode': false},
        'request': {'useSsl': true},
      },
      'serviceIntegrityDimensions': {
        'poToken': playerPoToken,
      },
      'contentCheckOk': true,
      'racyCheckOk': true,
    };

    final tParam = _generateTParam();
    final url = '$_youtubeiV1Gapis/player?prettyPrint=false&t=$tParam&id=$videoId';

    final headers = <String, String>{
      'User-Agent': ua,
      'Content-Type': 'application/json',
      'X-Goog-Api-Format-Version': '2',
    };
    // MWEB 登录态注入 Cookie(且 SAPISIDHASH/X-Origin — web 风格 auth on web UA OK)
    if (injectCookie) {
      final authHeaders =
          YtAuthService.buildAuthHeaders(origin: 'https://www.youtube.com');
      if (authHeaders != null) {
        headers.addAll(authHeaders);
      }
    }

    final resp = await _dio.post<Map<String, dynamic>>(
      url,
      data: jsonEncode(body),
      options: Options(
        headers: headers,
        responseType: ResponseType.json,
      ),
    );
    if (resp.statusCode != 200 || resp.data == null) {
      throw Exception('/player HTTP ${resp.statusCode}');
    }
    final data = resp.data!;
    final ps = data['playabilityStatus'];
    final status = ps?['status'] as String?;
    if (status != 'OK') {
      throw Exception(
          '/player playabilityStatus=$status reason=${ps?['reason']}');
    }
    final sd = data['streamingData'] as Map<String, dynamic>?;
    if (sd == null) throw Exception('streamingData missing');

    final hlsManifestUrl = sd['hlsManifestUrl'] as String?;
    final durMs = int.tryParse(
            (data['videoDetails']?['lengthSeconds'] as String?) ?? '0') ??
        0;
    final formats = <YtIntFormat>[];
    final adaptive = sd['adaptiveFormats'] as List? ?? const [];
    final progressive = sd['formats'] as List? ?? const [];
    for (final f in [...progressive, ...adaptive]) {
      final m = f as Map<String, dynamic>;
      var streamUrl = m['url'] as String?;
      streamUrl ??= m['signatureCipher'] as String?;
      if (streamUrl == null) continue;
      if (!streamUrl.contains('pot=')) {
        streamUrl =
            '$streamUrl&pot=${Uri.encodeComponent(streamingPoToken)}';
      }
      final mime = (m['mimeType'] as String?) ?? '';
      final hasV = mime.startsWith('video/');
      final hasA = mime.startsWith('audio/');
      final at = m['audioTrack'] as Map<String, dynamic>?;
      String? audioTrackId;
      bool isDubbed = false;
      if (at != null) {
        audioTrackId = at['id'] as String?;
        isDubbed = (at['audioIsDefault'] == false);
      }
      final lower = streamUrl.toLowerCase();
      if (lower.contains('acont%3ddubbed') || lower.contains('acont=dubbed')) {
        isDubbed = true;
      }
      formats.add(YtIntFormat(
        itag: m['itag'] as int,
        url: streamUrl,
        mimeType: mime,
        bitrate: m['bitrate'] as int? ?? 0,
        qualityLabel: m['qualityLabel'] as String?,
        width: m['width'] as int?,
        height: m['height'] as int?,
        fps: m['fps'] as int?,
        container: _containerFromMime(mime),
        codec: _codecFromMime(mime),
        hasVideo: hasV,
        hasAudio: hasA || (hasV && (m['audioChannels'] != null)),
        audioTrackId: audioTrackId,
        isDubbedAudio: isDubbed,
      ));
    }
    return YtInnertubePlayerResponse(
      formats: formats,
      hlsManifestUrl: hlsManifestUrl,
      durationMs: durMs > 0 ? durMs * 1000 : null,
      visitorData: visitorData,
    );
  }

  static String _containerFromMime(String mime) {
    final s = mime.toLowerCase();
    if (s.contains('mp4')) return 'mp4';
    if (s.contains('webm')) return 'webm';
    if (s.contains('m4a')) return 'm4a';
    return 'unknown';
  }

  static String _codecFromMime(String mime) {
    final re = RegExp(r'codecs="([^"]+)"');
    final m = re.firstMatch(mime);
    return m?.group(1) ?? '';
  }

  /// CPN = Client Playback Nonce (16 char base64ish),YT 要求每个 player 请求生成
  static String _generateCpn() {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_';
    final r = DateTime.now().millisecondsSinceEpoch;
    final buf = StringBuffer();
    var seed = r;
    for (var i = 0; i < 16; i++) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      buf.write(chars[seed % chars.length]);
    }
    return buf.toString();
  }

  /// t = unix seconds in base36(NewPipe generateTParameter)
  static String _generateTParam() {
    return (DateTime.now().millisecondsSinceEpoch ~/ 1000).toRadixString(36);
  }
}
