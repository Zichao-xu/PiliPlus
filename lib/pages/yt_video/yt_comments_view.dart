// YT 评论视图。视觉风格沿用 PiliPlus 评论区(头像 + 名字 + 时间 + 正文 + 点赞数)。

import 'package:PiliPlus/common/widgets/loading_widget/http_error.dart';
import 'package:PiliPlus/common/widgets/yt_translatable_text.dart';
import 'package:PiliPlus/models_new/youtube/yt_comment.dart';
import 'package:PiliPlus/services/youtube/yt_comments.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/yt_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

class YtCommentsView extends StatefulWidget {
  const YtCommentsView({super.key, required this.videoId});
  final String videoId;

  @override
  State<YtCommentsView> createState() => _YtCommentsViewState();
}

class _YtCommentsViewState extends State<YtCommentsView>
    with AutomaticKeepAliveClientMixin {
  final _service = YtCommentsService();
  final _comments = <YtComment>[];
  String? _nextToken;
  bool _firstLoading = true;
  bool _loadingMore = false;
  String? _errMsg;
  late final ScrollController _scrollCtr;
  bool get _autoTranslate => GStorage.setting
      .get(SettingBoxKey.ytAutoTranslateMeta, defaultValue: false) as bool;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollCtr = ScrollController()..addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollCtr
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtr.position.pixels >=
            _scrollCtr.position.maxScrollExtent - 200 &&
        !_loadingMore &&
        _nextToken != null) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    try {
      final page = await _service.fetchFirstPage(widget.videoId);
      if (!mounted) return;
      setState(() {
        _comments
          ..clear()
          ..addAll(page.comments);
        _nextToken = page.nextToken;
        _firstLoading = false;
        _errMsg = page.comments.isEmpty && page.nextToken == null
            ? '该视频评论暂未开放或无评论'
            : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _firstLoading = false;
        _errMsg = '加载失败: $e';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _nextToken == null) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _service.fetchByToken(_nextToken!);
      if (!mounted) return;
      setState(() {
        _comments.addAll(page.comments);
        _nextToken = page.nextToken;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _firstLoading = true;
      _errMsg = null;
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_firstLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_comments.isEmpty) {
      return HttpError(
        isSliver: false,
        errMsg: _errMsg ?? '还没有评论',
        onReload: _refresh,
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        controller: _scrollCtr,
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 32),
        itemCount: _comments.length + 1,
        separatorBuilder: (_, _) =>
            const Divider(height: 1, indent: 60, thickness: 0.4),
        itemBuilder: (context, i) {
          if (i == _comments.length) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: _nextToken == null
                    ? Text('— 没有更多了 —',
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey.shade500))
                    : _loadingMore
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const SizedBox.shrink(),
              ),
            );
          }
          return _buildComment(_comments[i]);
        },
      ),
    );
  }

  Future<void> _openReplyDialog(YtComment c) async {
    if (c.createReplyParams == null) {
      SmartDialog.showToast('该评论暂不可回复');
      return;
    }
    if (!YtAuthService.isLoggedIn) {
      SmartDialog.showToast('需先登录 YouTube 才能回复');
      await Get.toNamed<bool>('/ytLogin');
      if (!mounted) return;
      if (!YtAuthService.isLoggedIn) return;
    }
    final ctr = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('回复 ${c.author}'),
        content: TextField(
          controller: ctr,
          autofocus: true,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: 'reply to: ${c.text.length > 40 ? '${c.text.substring(0, 40)}…' : c.text}',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctr.text.trim()),
            child: const Text('发送'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty) return;
    try {
      await _service.createReply(c.createReplyParams!, result);
      if (mounted) SmartDialog.showToast('回复已发送');
    } catch (e) {
      final msg = e.toString();
      final friendly = msg.contains('INVALID_ARGUMENT')
          ? '回复失败:token 已失效,刷新评论再试'
          : '回复失败:$e';
      if (mounted) SmartDialog.showToast(friendly);
    }
  }

  Widget _buildComment(YtComment c) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipOval(
            child: SizedBox(
              width: 36,
              height: 36,
              child: c.authorAvatarUrl != null
                  ? CachedNetworkImage(
                      imageUrl: c.authorAvatarUrl!,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) =>
                          Container(color: Colors.grey.shade300),
                    )
                  : Container(color: Colors.grey.shade300),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        c.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    Text(
                      c.publishedTimeText,
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                YtTranslatableText(
                  text: c.text,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.45,
                    color: theme.colorScheme.onSurface,
                  ),
                  selectable: true,
                  autoTranslate: _autoTranslate,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.thumb_up_outlined,
                        size: 14, color: theme.colorScheme.outline),
                    const SizedBox(width: 4),
                    Text(
                      c.likeCountText.isEmpty ? '0' : c.likeCountText,
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    if (c.replyCount > 0) ...[
                      const SizedBox(width: 14),
                      Icon(Icons.forum_outlined,
                          size: 13, color: theme.colorScheme.outline),
                      const SizedBox(width: 4),
                      Text(
                        '${c.replyCount}',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                    const SizedBox(width: 14),
                    // 短按"回复"按钮 — PiliPlus 评论风格
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _openReplyDialog(c),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.reply_outlined,
                                size: 13, color: theme.colorScheme.primary),
                            const SizedBox(width: 3),
                            Text(
                              '回复',
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
