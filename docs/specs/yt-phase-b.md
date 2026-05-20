# Phase B — 切回 dual-client + 5 项 wire

## 前置:依赖 dual-client 起步

按 [docs/sessions/2026-05-18-state-checkpoint.md](../sessions/2026-05-18-state-checkpoint.md) 4 处改回。

## 子任务

### B0. 切回 dual-client(基线)

按 checkpoint 4 处:
1. `yt_video.dart::fetchMuxedStreams` — 三段热备 `ANDROID_VR → MWEB(登录态) → yt_explode`
2. `yt_video.dart::_streamClients` — 加 `androidVr / safari / mweb` 前置
3. `yt_video.dart::_fetchMuxedOnce` `authEnabled = YtAuthService.isLoggedIn`
4. `yt_video_page.dart::_startPlayback` 注入 Cookie 到 mpv setMediaHeader

### B1. #1 自动画质(Netflix 风格 HLS 无缝)

`yt_video_page.dart::_startPlayback`:
- 起播时,如设置 `ytDefaultQuality == 'auto'`,优先选 `qualityLabel == '自动 (HLS)'` 的流(`_innertubeToMuxedOptions` 已加 HLS 在最前)
- 其他档位:挑最接近 `360p/720p/1080p` 的非 HLS 流
- HLS 自带 ABR,mpv 内部 demux 时根据带宽 seamless 切换分段画质

### B5. 设置项 wire

- `ytDefaultQuality`:`_startPlayback` 选 stream 时按设置匹配
- `ytSubtitleDefault`:`_setSubtitle` 自动选首条时按设置走(off/native/translate)
- `ytSubtitleTranslateLang`:translate 模式下用此值

### B3. YT 点赞/点踩 API

`yt_video.dart` 新增 `YtVideoService.likeVideo(videoId)` / `dislikeVideo` / `removeRating`:
- POST `https://www.youtube.com/youtubei/v1/like/like` 等 endpoint
- Body:`{videoId, context.client = ANDROID_VR, target.videoId = videoId}`
- Header:`Authorization: SAPISIDHASH ...` + `Cookie: ...`(走 `YtAuthService.buildAuthHeaders`)

`yt_video_page.dart::_actionsRow`:
- 点赞按钮:已登录态 → 调 likeVideo,成功 toast + 视觉态切换
- 已点过赞:再点 → removeRating,toast

### B6. 评论翻译

`yt_comments_view.dart` 每条评论的文本用 `YtTranslatableText` 包,autoTranslate flag 走 `ytAutoTranslateMeta` 设置。

### B7. 评论长按回复

`yt_comments_view.dart`:
- `GestureDetector.onLongPress` → 弹底部 sheet 含「回复」+「翻译」选项
- 「回复」→ 弹 TextField + 发送按钮
- 发送 → POST `https://www.youtube.com/youtubei/v1/comment/create_comment_reply` + SAPISIDHASH

## 实施顺序

按 minimal first:B0 → B1 → B5 → B3 → B6 → B7。每步自测 + IPA。

## 风险

- B0 切回后,反爬节点不好的话**所有视频又会 LOGIN_REQUIRED**。fallback yt_explode 360p 仍存。
- B3/B7 write API 是 Google 内部约定,可能格式不对挂 HTTP 400。需要试错。
- Test 用户号是 AI 测试号,可放心试错。
