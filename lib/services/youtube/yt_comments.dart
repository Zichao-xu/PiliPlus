// 直接调 InnerTube `/next` 端点拿评论数据。
// 绕过 yt_explode_dart 3.1.0 的 commentsClient(它在 YT 新 ViewModel 结构下崩 null check)。
//
// 流程:
// Step 1: POST /next videoId → 扫 engagementPanels 找 commentSectionRenderer 的 continuation token
// Step 2: POST /next continuation → 解 commentEntityPayload 数组(深度扫整个响应)
// Step 3: 翻页用响应里的下一个 continuation token

import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/models_new/youtube/yt_comment.dart';
import 'package:PiliPlus/utils/yt_auth.dart';

class YtCommentsService {
  static const _clientContext = {
    'client': {
      'clientName': 'WEB',
      'clientVersion': '2.20241204.01.00',
      'hl': 'zh-Hans',
      'gl': 'US',
    },
  };

  /// 第一次拿评论:videoId → 评论 section continuation → 第一页
  Future<YtCommentsPage> fetchFirstPage(String videoId) async {
    final token = await _fetchCommentSectionToken(videoId);
    if (token == null) {
      return const YtCommentsPage(comments: [], nextToken: null);
    }
    return fetchByToken(token);
  }

  /// 续页:用上一页返回的 continuation token
  Future<YtCommentsPage> fetchByToken(String token) async {
    final json = await _post({
      'context': _clientContext,
      'continuation': token,
    });
    return _parsePage(json);
  }

  // ---- internals ----

  Future<String?> _fetchCommentSectionToken(String videoId) async {
    final json = await _post({
      'context': _clientContext,
      'videoId': videoId,
    });
    final panels = json['engagementPanels'] as List?;
    if (panels == null) return null;
    for (final p in panels) {
      final renderer = (p as Map)['engagementPanelSectionListRenderer'];
      if (renderer is! Map) continue;
      final id = renderer['panelIdentifier']?.toString() ?? '';
      if (!id.contains('comment')) continue;
      String? token;
      void walk(dynamic n) {
        if (token != null) return;
        if (n is Map) {
          final t = n['continuationCommand']?['token'];
          if (t is String && t.isNotEmpty) {
            token = t;
            return;
          }
          n.values.forEach(walk);
        } else if (n is List) {
          n.forEach(walk);
        }
      }
      walk(renderer);
      if (token != null) return token;
    }
    return null;
  }

  YtCommentsPage _parsePage(Map<String, dynamic> json) {
    // 1) 扫整个响应找 commentEntityPayload(深度遍历)
    final payloads = <Map<String, dynamic>>[];
    String? nextToken;
    void walk(dynamic n) {
      if (n is Map) {
        final p = n['commentEntityPayload'];
        if (p is Map) payloads.add(Map<String, dynamic>.from(p));
        // continuation token (next page)
        final tok = n['continuationCommand']?['token'];
        if (tok is String && tok.isNotEmpty && nextToken == null) {
          nextToken = tok;
        }
        n.values.forEach(walk);
      } else if (n is List) {
        n.forEach(walk);
      }
    }
    walk(json);

    final comments = <YtComment>[];
    for (final p in payloads) {
      final props = p['properties'] as Map?;
      final author = p['author'] as Map?;
      final toolbar = p['toolbar'] as Map?;
      final avatar = p['avatar'] as Map?;
      if (props == null) continue;
      // 只取顶层评论(replyLevel == 0),回复留 M+ 阶段做
      final replyLevel = (props['replyLevel'] as num?)?.toInt() ?? 0;
      if (replyLevel != 0) continue;
      final id = props['commentId']?.toString() ?? '';
      final text = props['content']?['content']?.toString() ?? '';
      final publishedTime = props['publishedTime']?.toString() ?? '';
      final name = author?['displayName']?.toString() ?? '匿名';
      final avatarUrl = _firstThumbnailUrl(avatar?['image']);
      final likeCountText = toolbar?['likeCountNotliked']?.toString() ?? '';
      final replyCountText = toolbar?['replyCount']?.toString() ?? '0';
      final replyCount = int.tryParse(replyCountText) ?? 0;
      // 在该 payload 子树范围内挖 createCommentReplyEndpoint.params
      // 兜底全树搜:NewPipe 在 2025 末后这条 path 浮动过几次,深度遍历最稳
      final replyParams = _findReplyParams(p);
      comments.add(YtComment(
        id: id,
        author: name,
        text: text,
        publishedTimeText: publishedTime,
        likeCountText: likeCountText,
        authorAvatarUrl: avatarUrl,
        replyCount: replyCount,
        createReplyParams: replyParams,
      ));
    }
    return YtCommentsPage(comments: comments, nextToken: nextToken);
  }

  /// 深度遍历找 `createCommentReplyEndpoint.params`(YT 真回复 token)。
  /// 没命中返回 null,UI 层据此禁用回复按钮。
  static String? _findReplyParams(dynamic node) {
    String? hit;
    void walk(dynamic n) {
      if (hit != null) return;
      if (n is Map) {
        final ep = n['createCommentReplyEndpoint'];
        if (ep is Map) {
          final p = ep['params'];
          if (p is String && p.isNotEmpty) {
            hit = p;
            return;
          }
        }
        n.values.forEach(walk);
      } else if (n is List) {
        n.forEach(walk);
      }
    }
    walk(node);
    return hit;
  }

  String? _firstThumbnailUrl(dynamic image) {
    if (image is Map) {
      final sources = image['sources'] as List?;
      if (sources != null && sources.isNotEmpty) {
        final url = (sources.first as Map?)?['url']?.toString();
        return url;
      }
    }
    return null;
  }

  /// 发评论回复。需要登录态(cookie + SAPISIDHASH 走 [YtAuthService.buildAuthHeaders])。
  /// `createReplyParams` 必须是 `createCommentReplyEndpoint.params` 的真 token,
  /// 不能用 commentId(会 INVALID_ARGUMENT)。
  Future<void> createReply(String createReplyParams, String text) async {
    if (!YtAuthService.isLoggedIn) {
      throw StateError('YouTube 未登录');
    }
    final body = {
      'context': _clientContext,
      'commentText': text,
      'createReplyParams': createReplyParams,
    };
    final client = HttpClient();
    try {
      final req = await client.postUrl(
        Uri.parse(
            'https://www.youtube.com/youtubei/v1/comment/create_comment_reply?prettyPrint=false'),
      );
      req.headers.contentType = ContentType.json;
      req.headers.set('Accept', 'application/json');
      req.headers.set('User-Agent',
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36');
      final auth =
          YtAuthService.buildAuthHeaders(origin: 'https://www.youtube.com');
      if (auth != null) {
        for (final e in auth.entries) {
          req.headers.set(e.key, e.value);
        }
      }
      req.write(jsonEncode(body));
      final res = await req.close();
      if (res.statusCode != 200) {
        final t = await res.transform(utf8.decoder).join();
        throw Exception('reply HTTP ${res.statusCode}: $t');
      }
    } finally {
      client.close();
    }
  }

  Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    final client = HttpClient();
    try {
      final req = await client.postUrl(
        Uri.parse(
            'https://www.youtube.com/youtubei/v1/next?prettyPrint=false'),
      );
      req.headers.contentType = ContentType.json;
      req.headers.set('Accept', 'application/json');
      req.headers.set('Accept-Language', 'zh-Hans,zh;q=0.9,en;q=0.8');
      req.headers.set('User-Agent',
          'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15');
      req.write(jsonEncode(body));
      final res = await req.close();
      final text = await res.transform(utf8.decoder).join();
      return jsonDecode(text) as Map<String, dynamic>;
    } finally {
      client.close();
    }
  }
}
