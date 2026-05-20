# Session: M3 — YouTube 视频详情(播放 + 简介) 收尾

## 1. 改动 / 新增文件清单

```
 M lib/models/common/video/source_type.dart   // 加 youtube 枚举
 M lib/pages/video/controller.dart            // isYtSource + initYtSource + 分发
 M lib/pages/video/view.dart                  // IntroPanel 分发 + 交互屏蔽
?? lib/common/widgets/video_card/yt_video_card_h.dart  // onTap 路由跳转
?? lib/models_new/youtube/yt_video_detail.dart
?? lib/pages/video/introduction/yt/controller.dart
?? lib/pages/video/introduction/yt/view.dart
?? lib/services/youtube/yt_video.dart
```

## 2. `isFileSource` 全部引用点分类表

| 文件 | 行号 | 分类 |
|---|---|---|
| controller.dart | 158, 165, 256, 350, 767, 829, 1348 | 禁交互判断 → 扩为 `(isFileSource \|\| isYtSource)` |
| controller.dart | 435, 437, 438, 791, 871, 1309, 1327 | file 专属分支 / reset → **不动**, YT 走自己分支 |
| view.dart | 97, 127, 165, 307, 350, 717, 973, 1003, 1012, 1246, 1257, 1317, 1378, 1416, 1733 | 禁交互判断 → 扩为 `(isFileSource \|\| isYtSource)` |
| header_control.dart | 多处 | 沿用 videoDetailCtr.isFileSource,已在 controller 层处理 |

## 3. setDataSource 调用形态

B 站现有(简化):
```dart
await plPlayerController.setDataSource(
  NetworkSource(
    videoSource: video ?? videoUrl!,
    audioSource: audio ?? audioUrl,
  ),
  seekTo: seek,
  duration: ...,
  isVertical: isVertical.value,
  aid: aid, bvid: bvid, cid: cid.value,
  autoplay: autoplay ?? _autoPlay.value,
  ...
);
```

YT 版本(在 `initYtSource` 末尾单独调):
```dart
await plPlayerController.setDataSource(
  NetworkSource(
    videoSource: url,
    audioSource: null,
  ),
  autoplay: true,
  duration: detail.duration,
);
```

## 4. `flutter analyze` 输出

```
Analyzing 5 items...
No issues found! (ran in 8.2s)
```

## 5. 关键决策

- **cid=0 占位**: 路由传 `cid: 0, aid: 0`。controller onInit 里 `cid = RxInt(args['cid'])` 正常执行; YT 不走 fileSource 分支,`cacheLocalProgress` 等 cid 敏感逻辑不会触发。YtIntroController 在 onInit 里把 `videoDetail.value.title` 设为 `ytVideoDetail?.title`,不依赖 bvid/cid。
- **DataSource 字段取舍**: YT muxed 流是单一 URL,只传 `videoSource` + `duration`; 不传 `audioSource`(muxed 已含音频)、`headers`、`videoQualities`、`aid/bvid/cid` 等 B 站专属字段。
- **cover/title 流**: 搜索卡片 onTap 时把 `cover` 和 `title` 写进 arguments; controller onInit 读取 `cover = RxString(args['cover'] ?? '')`。简介区 title 从 `ytVideoDetail` 读,cover 通过现有 Rx 流给播放器头图。

## 6. 已知风险清单

- iOS media_kit 是否真能播 YT CDN URL — **未真机验证**,M0 仅在 macOS 用 mpv 验证过 URL 可播。
- cid=0 若后续被其他逻辑(如 heartbeat、弹幕、历史记录)误用,可能以 "0" 为 key 污染本地存储 — 当前已屏蔽 YT 路径进入这些逻辑,但需持续检查。
- media_kit 对 YT CDN 是否需要 `User-Agent` / `Range` header — **未验证**,若真机播放失败优先排查此点。
- YT muxed 流封顶 360p,画质体验有限。

## 7. 给 M4 评论的注意点

- commentsClient / reply 模块已知有兼容性问题(参见 M0 session log),接 YT 评论前需确认接口形态,避免直接沿用 B 站评论 client 崩溃。
- `initYtSource` 当前只处理了播放成功路径; M4 如需做"播放失败自动切下一个视频"等交互,需在 `catch` 块内补充状态回调,不要只 toast。
