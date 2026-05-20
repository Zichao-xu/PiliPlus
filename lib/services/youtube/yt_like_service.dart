// YouTube 点赞 / 点踩 / 收藏 (写) API
//
// 走 /youtubei/v1/like/{like,dislike,removelike} + SAPISIDHASH。
// IOS/ANDROID UA + cookie 在 server 端 today 经常被拒,所以这里用 ANDROID_VR client
// 拼 web 风格 Authorization;同 yt_innertube_player 同套 auth header 策略。
//
// 各 endpoint payload 是 `{target: {videoId}, context: {client...}}`。

import 'dart:convert';

import 'package:PiliPlus/utils/yt_auth.dart';
import 'package:dio/dio.dart';

enum YtLikeStatus {
  none,
  liked,
  disliked,
}

class YtLikeService {
  YtLikeService._();
  static final instance = YtLikeService._();

  static const _endpointLike =
      'https://www.youtube.com/youtubei/v1/like/like?prettyPrint=false';
  static const _endpointDislike =
      'https://www.youtube.com/youtubei/v1/like/dislike?prettyPrint=false';
  static const _endpointRemove =
      'https://www.youtube.com/youtubei/v1/like/removelike?prettyPrint=false';

  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';
  static const _clientVersion = '2.20260120.01.00';

  final _dio = Dio(BaseOptions(
    receiveTimeout: const Duration(seconds: 15),
    sendTimeout: const Duration(seconds: 10),
  ));

  Future<void> like(String videoId) => _call(_endpointLike, videoId);
  Future<void> dislike(String videoId) => _call(_endpointDislike, videoId);
  Future<void> removeRating(String videoId) =>
      _call(_endpointRemove, videoId);

  Future<void> _call(String url, String videoId) async {
    if (!YtAuthService.isLoggedIn) {
      throw StateError('YouTube 未登录,无法操作');
    }
    final body = {
      'target': {'videoId': videoId},
      'context': {
        'client': {
          'clientName': 'WEB',
          'clientVersion': _clientVersion,
          'hl': 'en',
          'gl': 'US',
        },
      },
    };
    final headers = <String, String>{
      'User-Agent': _ua,
      'Content-Type': 'application/json',
      'X-Youtube-Client-Name': '1',
      'X-Youtube-Client-Version': _clientVersion,
    };
    final auth =
        YtAuthService.buildAuthHeaders(origin: 'https://www.youtube.com');
    if (auth != null) headers.addAll(auth);

    final resp = await _dio.post<Map<String, dynamic>>(
      url,
      data: jsonEncode(body),
      options: Options(
        headers: headers,
        responseType: ResponseType.json,
      ),
    );
    if (resp.statusCode != 200) {
      throw Exception('YT like API HTTP ${resp.statusCode}');
    }
  }
}
