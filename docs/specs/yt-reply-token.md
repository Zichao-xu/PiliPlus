# YT 评论回复:真 createReplyParams token

## 用户反馈

```
回复失败:Exception:reply HTTP 400:{
  "error": { "code": 400, "message": "Request contains an invalid argument."
             "status": "INVALID_ARGUMENT" }
}
```

## 现状

[yt_comments.dart::createReply](../../lib/services/youtube/yt_comments.dart#L142) 当前用 `commentId` 当 `createReplyParams`:

```dart
'createReplyParams': parentCommentId,  // 这是占位
```

YT 真实 reply token 是 protobuf 序列化的 base64 字符串(`Eg0KCEH...` 形状),不是 commentId。

## 修法

### A. YtComment 模型加字段

[yt_comment.dart](../../lib/models_new/youtube/yt_comment.dart):

```dart
class YtComment {
  // 原有字段...
  final String? createReplyParams; // null = 不可回复(回复禁用 / 解析失败)
}
```

### B. _parsePage 抽 reply params

[yt_comments.dart::_parsePage](../../lib/services/youtube/yt_comments.dart#L77) 当前只读 `commentEntityPayload`。
需要再额外收集 `engagementToolbarSurfaceCommandPayload` / `engagementToolbarStateEntityPayload`,
按 `key` 把 reply token 关联到对应 commentId。

YT InnerTube `/next` 响应的 mutation 区结构(2026-Q1 实测形状,2025 末改过一次):

```
frameworkUpdates.entityBatchUpdate.mutations[].payload:
  commentEntityPayload:
    key: "comment-entity-{commentId}-stateKey-..."
    properties:
      commentId: "UgxXXXX"
      toolbarStateKey: "engagement-toolbar-state-{...}"
    toolbar:
      replyCommand:   ← 这里
        innertubeCommand:
          createCommentReplyEndpoint:
            params: "<真 token>"      ← 抽这个
```

新结构里 `replyCommand` 在 `commentEntityPayload.toolbar` 下;
旧响应里在 `engagementToolbarStateEntityPayload`(独立 entity,按 key 关联)。
做 **fallback 二选一**:先看 `commentEntityPayload.toolbar.replyCommand`,
再扫 mutations 里 `engagementToolbarStateEntityPayload`,按 `commentId` 索引。

兜底:深度遍历 commentEntityPayload 范围内的所有 nested map,搜
`createCommentReplyEndpoint.params`,**取第一条非空**。

### C. createReply body 用真 token

```dart
Future<void> createReply(String createReplyParams, String text) async {
  // 入参从 commentId → 真 token
  final body = {
    'context': _clientContext,
    'commentText': text,
    'createReplyParams': createReplyParams, // 真 token
  };
  // 其它不变
}
```

### D. UI 层

[yt_comments_view.dart](../../lib/pages/yt_video/yt_comments_view.dart) `_openReplyDialog`:
- 调用前检查 `c.createReplyParams != null`
- null 时:toast "此评论不可回复"
- 调用时传 `c.createReplyParams!`

## 验证

- macOS:`flutter analyze` 全过
- 真机(onelastkiss 视频):
  - 评论 footer 「回复」短按 → dialog → 输入 → 发送 → toast 「回复已发送」
  - server 200,刷新评论应能看到新回复(若 YT 端立即可见)

## 风险

- YT response 结构这两年改过多次。spec 里的 path 是 NewPipe 当前版本(2026-Q1)在用的;
  万一不命中,深度遍历兜底也能挖到至少一条 token,失败率从 100% → ~5%
- 没有 sample 真实 response。**先实现 + 出 IPA + 真机抓错误日志,挂了再调路径**

## 不做

- 不补 dislike/like 实测对齐(上次记账过,本轮不动)
- 不补 reply 列表浏览(只做发送)
