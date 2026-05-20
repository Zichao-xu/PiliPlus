class YtComment {
  final String id;
  final String author;
  final String text;
  final String publishedTimeText; // YT 原文如 "3 天前"
  final String likeCountText; // YT 原文如 "1.2K"
  final String? authorAvatarUrl;
  final int replyCount;
  /// YT InnerTube `createCommentReplyEndpoint.params`(protobuf base64)。
  /// null = 解析未命中 / 评论禁回复;不能 fallback 用 commentId(会 INVALID_ARGUMENT)
  final String? createReplyParams;
  const YtComment({
    required this.id,
    required this.author,
    required this.text,
    required this.publishedTimeText,
    required this.likeCountText,
    this.authorAvatarUrl,
    this.replyCount = 0,
    this.createReplyParams,
  });
}

class YtCommentsPage {
  final List<YtComment> comments;
  final String? nextToken;
  const YtCommentsPage({required this.comments, this.nextToken});
}
