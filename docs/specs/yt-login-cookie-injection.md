# YT 登录 cookie 注入 — 解锁 LOGIN_REQUIRED

> 紧接 `yt-manual-play-stable` 之后。自测发现 YT 反爬升级:同一视频几小时前 PoToken 还能放,现在返回
> `LOGIN_REQUIRED reason=Sign in to confirm you're not a bot`。`YtAuthService.cookies` 已经能存,但
> 取流路径完全没用。这个 spec 把 cookie 接上,**登录后视频能播**就算目标达成。

## 目标

- 登录态(`YtAuthService.isLoggedIn == true`)下:
  - `YtInnertubePlayer.fetchPlayer` 调 `/player` 时带 `Authorization: SAPISIDHASH ...` + `Cookie: ...`
  - mpv 拉 stream URL / HLS 时带 `Cookie:` header
  - `fetchMuxedStreams` 的 yt_explode 分支放开 split 高画质流(`_fetchMuxedOnce` 里 `authEnabled` 从常量 false 改成 `YtAuthService.isLoggedIn`)
- 未登录态:完全不变,行为同当前

## 改动

### 1. `lib/services/youtube/yt_innertube_player.dart`

`_fetchPlayerOnce`:
- 把 `YtAuthService.buildAuthHeaders(origin: 'https://www.youtube.com')` 的结果 merge 进 dio request headers
- 未登录 → 返回 null → 跳过 merge,行为不变
- 还需要在 body 的 `context.user` 里加 `onBehalfOfUser`,但 NewPipe 实测只加 header 也 work,先这样

### 2. `lib/pages/yt_video/yt_video_page.dart::_startPlayback`

`player.setMediaHeader(userAgent: ...)` 处:
- 已经有 userAgent。把 Cookie 一并 set。
- media_kit 的 `setMediaHeader` 接收 `extraHeaders` (`Map<String, String>?`)
- 拼 cookie 字符串 `name=value; name=value`,传 `extraHeaders: {'Cookie': cookieStr}`

### 3. `lib/services/youtube/yt_video.dart`

`_fetchMuxedOnce`:
- `const authEnabled = false` → `final authEnabled = YtAuthService.isLoggedIn`
- 现有 `_collectSplitStreams` 私有方法 already 写好,只是被 false 卡着,这下放开

## 不做(本轮)

- 不改 PoToken WebView 内 cookie 注入 — PoToken 是 BotGuard,与 user auth 解耦,有 visitorData 就够
- 不切到 WEB client(NewPipe 登录路径) — IOS client + cookie 先试,若仍 LOGIN_REQUIRED 再升级
- 不实现 SAPISIDHASH 算法 — `YtAuthService.buildAuthHeaders()` 已经写好

## 验收

1. **未登录**(`YtAuthService.cookies == null`):
   - 走当前路径,行为不变(仍可能 LOGIN_REQUIRED 但错误清晰)
2. **登录**(粘 cookie 后):
   - macOS Debug 上同一视频(0Uhh62MUEic) 应该能播 — Innertube `/player` 返回 OK
   - 画质菜单包含 720p / 1080p split 流(yt_explode 分支放开后)
   - mpv 实际开流时 stream URL 带 Cookie,不再 403

## 风险

- YT 对登录用户 throttle 不同于 anonymous,可能有别的限制(年龄限制视频 / 地区限制)。先聚焦 LOGIN_REQUIRED 这一个目标。
- IOS client 是否真接受 cookie auth 不确定。retry-without-poToken 那条线如果还失败,考虑切到 WEB client。

## 交付

- iOS Release IPA: `~/Desktop/PiliPlus-cookie-auth-2026-05-18.ipa`
- 自测:macOS Debug 跑通登录后播放(需用户粘 cookie)
