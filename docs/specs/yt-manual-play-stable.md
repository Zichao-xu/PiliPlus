# YT 手动播放 + 加载稳定化

> 真机反馈:进入 YT 视频起不来。判断:PoToken WebView 真机上偶发卡死,无超时。
> 当前 working tree 已经把 UI 改成手动播放(进入页面不自动起播,点 ▶ 才走 fetch),
> 本 spec 补稳定性 + 完善错误展示。

## 改动范围

### 1. `lib/services/youtube/yt_potoken_service.dart`

- `_doInit()` 内 `callAsyncJavaScript(runBotGuard)` 加 `.timeout(20s)` → 超时 throw `YtPoTokenException('runBotGuard timeout')`
- `generatePoToken()` 内 `callAsyncJavaScript(obtainPoToken)` 加 `.timeout(10s)` → 超时 throw `YtPoTokenException('obtainPoToken timeout')`
- `loaded.future.timeout(10s)` 已有,保留

### 2. `lib/services/youtube/yt_video.dart`

`fetchMuxedStreams` Innertube path 外层裹 `.timeout(25s)` → 超时直接 catch,进入 yt_explode 360p fallback。
fallback 失败时把两层错都串起来 throw,方便诊断。

### 3. `lib/pages/yt_video/yt_video_page.dart`

`_startPlayback` catch 块的 error 显示加换行 + 多行展示,让 SelectableText 能完整看到。

## 不做

- 不改手动播放 UI(已 OK)
- 不改登录入口(已 3 处都有)
- 不动 PoToken HTML / Innertube 调用结构

## 验收

- macOS Debug 跑通:进 YT 视频显示封面 + ▶,点 ▶ 后 25s 内有画或有明确错误
- iOS Release IPA 给到 ~/Desktop,文件名带 `manual-play-stable`
