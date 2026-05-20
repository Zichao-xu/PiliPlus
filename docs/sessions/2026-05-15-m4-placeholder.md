# 2026-05-15 M4 — YouTube 评论占位

> 上级 spec: `docs/specs/multi-source-mvp.md` § M4
> 决定: **占位实现**(等上游库修)
> 执行: 军师亲做

## 结论

M4 评论 tab **UI 设计到位、内容占位**。等 `youtube_explode_dart` 上游修评论 API 后,改一处即可接入真评论。

## Spike 实测

`youtube_explode_dart 3.1.0`(pub.dev 已是最新)的 `commentsClient.getComments(video)` 在 3 个不同 videoId(`dQw4w9WgXcQ` / `vif8NQcjVf0` / `9bZkp7q19f0`)全部崩同一处:

```
_Comment._commentRenderer (comments_client.dart:141)
 → Null check operator used on a null value
```

**根因**: YouTube 改了 `commentRenderer` 响应结构(ViewModel 化趋势,2024-2025 业内已知),库内强制 `!` 解 null。

**spike artifact**: `scratch/yt_poc/bin/comments_v2.dart`(保留作回归验证用 —— 上游修了之后跑这个能立即确认)

## 设计选择(用户拍板)

A. **占位**(选这个) — UI tab 到位,内容显示空状态文案,等库修
B. fork patch + 自己解新结构 — 2-4 小时大工程,YouTube 还会再改
C. 跳过

理由: MVP 优先,M4 等用户在意时回头打通。

## 实现

`lib/pages/yt_video/yt_video_page.dart`:
- 加 `SingleTickerProviderStateMixin` + `TabController(length: 2)`
- 视频播放器下方加 TabBar(`简介` / `评论`)
- TabBarView:
  - 简介 → 原 `_buildIntro` 内容
  - 评论 → `HttpError(errMsg: 'YouTube 评论暂未启用\n等待上游库适配新版接口')` —— **复用 PiliPlus 评论页同款空状态组件**,视觉零割裂

`HttpError` widget 是 PiliPlus 本身评论页"还没有评论"用的占位组件 — 这个选择确保 UI 风格一致。

## 改动文件清单

```
M lib/pages/yt_video/yt_video_page.dart   # +TabBar +TabBarView +_buildCommentsPlaceholder
```

仅 1 个文件,~30 行净增。`flutter analyze` 0 issues。

## 真评论接入路径(将来)

只要上游库 fix `comments_client.dart:141` 的 null cast(适配新 ViewModel 结构),就改一处:

```dart
// 把 _buildCommentsPlaceholder() 换成:
// YtCommentsView(videoId: _videoId)   ← 新 widget,内部调 service
```

需要写: `lib/services/youtube/yt_comments.dart` + `lib/pages/yt_video/comments_view.dart`(走 LoadingState 范式)+ model。**MVP 内不做**。

## 给后续的注意点

- YouTube 接口变动频率高,新评论 API 上线/库修复后做回归测试,先跑 `scratch/yt_poc/bin/comments_v2.dart`
- 如果 1-2 个月内库还没修,考虑短期 fork patch(用 git override),不要等
- 二级回复(reply-to-reply)MVP 不展开,只显示"N 条回复"静态计数
