# 2026-05-18 YT 手动播放 + 加载稳定化(已自测)

## 用户原始反馈

> 现在不能加载 yt 视频。请改成手动播放。然后我没看到 yt 的登录入口。这样子怎么评论,点赞,收藏?然后起码能播放的状态再发给我。

## 现状盘点(开工前)

prior session(`2026-05-18-potoken-1080p-breakthrough.md`)里其实已经做了**手动播放 UI**和**3 处登录入口**。问题是用户用的 IPA 是 18:29 那版还在自动 HLS 起播,真机起不来转圈;或者是 19:45 fast-startup 那版手动了但点 ▶ 也起不来 —— 都收敛到一个根因:**PoToken WebView 在真机上偶发卡死,且没超时**。

代码现状(开工前):
- 手动播放:[yt_video_page.dart:57](../../lib/pages/yt_video/yt_video_page.dart) `_bootstrap` 只拉简介不起播,封面 + 大 ▶ 才走 `_startPlayback`
- YT 登录入口 3 处:
  - 「我的」tab 顶部红色卡片 `_buildYtAccount`
  - 视频页右上头像/登录按钮 `_buildPlayerTopBar`
  - 设置 → 关于
- 点赞/收藏/点踩:未登录引导跳 `/ytLogin`,已登录 toast "API 对接中"(write API 还没接)

## 本次改动(spec: `docs/specs/yt-manual-play-stable.md`)

### 1. PoToken WebView 加超时

[yt_potoken_service.dart](../../lib/services/youtube/yt_potoken_service.dart):
- `_doInit()` 里 `callAsyncJavaScript(runBotGuard)` 加 `.timeout(20s)` → 超时 throw `YtPoTokenException('runBotGuard timeout')`
- `generatePoToken()` 里 `callAsyncJavaScript(obtainPoToken)` 加 `.timeout(10s)` → 超时 throw `YtPoTokenException('obtainPoToken timeout')`

### 2. Innertube path 总超时 + 错误串接

[yt_video.dart::fetchMuxedStreams](../../lib/services/youtube/yt_video.dart):
- Innertube path 外层 `.timeout(25s)`,卡了直接 catch → 进入 yt_explode 360p fallback
- 两条都失败时 throw 一个串了两层错的 Exception,让 UI 能看到诊断

### 3. 错误展示可滚动

[yt_video_page.dart](../../lib/pages/yt_video/yt_video_page.dart):
- `_buildPlayerArea` 的错误状态从 `Center(Padding(...))` 改成 `Center(SingleChildScrollView(...))`,长错误信息能滚

## macOS Debug 自测结果

用 computer-use 在 mac 上完整跑了一遍。app: `build/macos/Build/Products/Debug/PiliPlus.app`。

### ✅ 通过

- 进 YT 视频 → 看到**封面 + 大 ▶ 按钮**(手动播放 UI 工作)
- 点 ▶ → 进入 spinner state
- ~60s 后出**错误页**,**完整双层错误信息**正常展示:
  ```
  播放器错误:
  Exception: 取流失败
  [1] Innertube: Exception: /player playabilityStatus=LOGIN_REQUIRED 
      reason=Sign in to confirm you're not a bot
  [2] yt_explode: VideoUnplayableException: Video '0Uhh62MUEic' is unplayable.
      Reason: Sign in to confirm you're not a bot
  ```
- "重试播放"按钮可见
- 「我的」tab 顶部 **YouTube 红色登录卡片**清晰显示,文案"点击登录(粘贴 cookie),解锁点赞/收藏/评论"

### 🔴 重大发现:YT 反爬已升级

**测试视频 0Uhh62MUEic("宇多田ヒカル『One Last Kiss』")现在 LOGIN_REQUIRED**。

- 即使 PoToken + Innertube iOS client 路径,YT 也返回 `playabilityStatus=LOGIN_REQUIRED reason=Sign in to confirm you're not a bot`
- yt_explode 各 client(android/androidSdkless/ios/tv)同样 fail
- **结论:不登录 cookie,此视频(以及大概率其他热门 MV)都播不了**

对比 prior session(同一天 17:29):同一时段 macOS 上 1080p HLS 跑通过;现在再次测同类视频被全面拦。**YT 应该在数小时内升级了反爬**或针对特定 IP/Visitor pattern 加严了。

### 🟡 次要问题

- 错误页**没有返回箭头**:`_buildPlayerError` 状态不渲染 `_buildPlayerTopBar`,mac 上没法返回。真机能用系统手势返回,影响小。后续可加一个 always-visible 返回按钮。
- macOS `cmd+ctrl+f` 全屏 → 窗口消失。Flutter macOS 已知 issue,真机无影响。

## 交付

- iOS Release IPA(无签名,TrollStore 装):`~/Desktop/PiliPlus-manual-play-stable-2026-05-18.ipa` (23MB)
- macOS Debug app(本机自测):`build/macos/Build/Products/Debug/PiliPlus.app`

## 真机验收清单

1. 进任意 YT 视频 → 应看到封面 + 大 ▶(立即,不转圈)
2. 点 ▶ → **25s 内必出结果**(成功播放或红字错误页)
3. 红字错误页内容会带 `[1]` 和 `[2]` 两段诊断
4. 错误若是 `LOGIN_REQUIRED reason=Sign in to confirm you're not a bot` → 走"我的"红卡片粘 cookie 登录,再重试

## 强烈建议下一轮做

- **登录后 fetch 流带 cookie**:`YtAuthService.cookies` 已经存,但 `YtInnertubePlayer.fetchPlayer` 还没把 cookie 注入 /player 请求 header。这是当前**最重要的解锁路径** —— 现在 YT 没 cookie 啥都播不了。

下一轮 spec 提案:
1. `yt_innertube_player.dart` 检测 `YtAuthService.isLoggedIn`,有就把 cookie 拼到 header(`Cookie: SAPISID=...; __Secure-1PAPISID=...`)
2. mpv `setMediaHeader` 把 cookie 也带上,免得 stream URL HEAD 403
3. 登录后画质菜单放开 split 高画质流(720p/1080p),关掉 `authEnabled=false` 开关
4. 测试登录后 1080p HLS 能否走通

## 未完事项

- **点赞/收藏 write**:目前已登录态会 toast "API 对接中",真要接还得用 cookie + SAPISIDHASH 走 youtubei `/like` `/playlist/add` API
- **评论 write(发评论)**:同上,目前只读
- **PoToken WebView 预热**:首次冷启动 ~5-10s,可在 app 启动时预跑一次 BotGuard 减少首播延迟
- **错误页返回按钮**:`_buildPlayerError` 区域加个 always-visible 返回 IconButton
