# 2026-05-18 PoToken + 1080p HLS 突破

## 一句话

把 NewPipe 的 BotGuard / poToken 方案完整移植成 Dart 实现,**绕过 YT 反爬,1080p 高画质播放跑通**(macOS Debug 实测)。

## 用户上次反馈

- 1080p 选了会回退 360p
- 字幕翻译基本不生效
- 速度慢、缓存完才播

我先做了"过滤掉不可播画质"的 stop-gap;然后用户拍板"copy 开源项目,巨人肩膀上"。调研完后选 **B 方案:PoToken WebView 上 1080p**,并要求今晚做完。

## 实现路径(NewPipe 移植)

### 1. PoToken 生成(`lib/services/youtube/yt_potoken_service.dart`)

- `assets/yt/po_token.html` — 直接抄 NewPipe `app/src/main/assets/po_token.html`(127 行)
- WebView 走 `HeadlessInAppWebView` 加载 HTML 框架,内含 `runBotGuard()` / `obtainPoToken()` 两个全局函数
- `_postBotGuardService()` 调 Google:
  - `https://www.youtube.com/api/jnn/v1/Create` 拿 challenge
  - `https://www.youtube.com/api/jnn/v1/GenerateIT` 拿 integrityToken
- 在 WebView 里跑 BotGuard VM(`callAsyncJavaScript` 才支持 Promise 返回)
- mint:对任意 identifier(visitorData 或 videoId)调 `obtainPoToken` 出 Uint8Array → base64url
- integrityToken ~6h 有效,期间可重复 mint 任意 identifier

**坑 1**:用 `evaluateJavascript` 跑 async 函数会返回 null —— 它不 await Promise。必须用 `callAsyncJavaScript`,该 API 返回 `CallAsyncJavaScriptResult { value, error }`。
**坑 2**:JS Util(parseChallengeData / parseIntegrityTokenData / u8ToBase64Url / descramble)要从 NewPipe `JavaScriptUtil.kt` 一比一移植到 Dart。

### 2. Innertube /player(`lib/services/youtube/yt_innertube_player.dart`)

走 **iOS 客户端**(免 signatureTimestamp,免 cipher 解密):

- 1) POST `/youtubei/v1/visitor_id` 拿 visitorData(WEB context)
- 2) mint cold-start poToken 绑 visitorData → `serviceIntegrityDimensions.poToken`
- 3) mint content-bound poToken 绑 videoId → 拼到流 URL `&pot=<pot>`
- 4) POST `https://youtubei.googleapis.com/youtubei/v1/player?t=<base36>&id=<vid>`
  - context.client = `IOS / clientVersion 21.03.2 / iPhone16,2 / iOS 18.7.2.22H124`
  - UA = `com.google.ios.youtube/21.03.2(iPhone16,2; U; CPU iOS 18_7_2 like Mac OS X)`
  - header `X-Goog-Api-Format-Version: 2`
- 解析 `streamingData.adaptiveFormats` + `streamingData.formats` + `hlsManifestUrl`

**实测 vif8NQcjVf0 返回 27 formats**,含:
- 2160p AV1/VP9 ✓ ✓
- 1440p AV1/VP9 ✓
- **1080p mp4 avc1.640028 H.264** ✓
- 1080p VP9
- 720p/480p/360p/240p/144p
- 5 条 audio-only(m4a 130k/50k + opus 136k/65k/49k)

**坑 3**:WEB clientVersion 老的(`2.20241126.00.00`)被 YT 直接 UNPLAYABLE。换 NewPipe HARDCODED 的 `2.20260120.01.00` 也不行,因为 WEB 客户端要 `signatureTimestamp`,要从 player.js 解析。索性用 iOS,免坑。

### 3. yt_video.dart 接入(`fetchMuxedStreams`)

```
Innertube + poToken → 27 formats (含 HLS master) → _innertubeToMuxedOptions()
                                ↓ 失败
                          yt_explode_dart (旧路径,muxed 360p 兜底)
```

`_innertubeToMuxedOptions` 把 Innertube formats 转成 `YtMuxedStreamOption` 列表:
- **HLS master 加到最前面**,qualityLabel="自动 (HLS)" — libmpv 自己处理 demux+ABR,最稳
- progressive muxed(若有,通常 360p)
- video-only split(配 m4a/webm audio,URL 已带 `&pot=`)

### 4. macOS 实测结果

- 默认起播选 "自动 (HLS)" → libmpv 拉 m3u8 → **画面立刻起来**,音视频同步,1080p 清晰
- 字幕自动启用第一条 English → 显示 "My first time at the Louvre was no big deal"
- 下行 374-838 KB/s 满速

## 关键文件

| 文件 | 行数 | 说明 |
|------|------|------|
| `assets/yt/po_token.html` | 127 | NewPipe BotGuard runner(JS 函数定义,无修改) |
| `lib/services/youtube/yt_potoken_service.dart` | ~250 | Dart BotGuard 控制 + Google API + 工具函数 |
| `lib/services/youtube/yt_innertube_player.dart` | ~250 | iOS client /player 调用 |
| `lib/services/youtube/yt_video.dart` | +120 | Innertube path 接入 + `_innertubeToMuxedOptions` |
| `lib/pages/about/view.dart` | +50 | 测试按钮 "测试 PoToken + /player" |
| `pubspec.yaml` | +1 | `- path: assets/yt/` |

## 交付物

- macOS Debug: `build/macos/Build/Products/Debug/PiliPlus.app`
- iOS IPA: `~/Desktop/PiliPlus-1080p-potoken-2026-05-18.ipa`(23MB)

## 真机验收清单

1. **HLS 自动播放**:打开任意 YT 视频,默认 "自动 (HLS)" 应立即起画
2. **画质菜单**:点画质标签 → 应见 `自动 (HLS) / 2160p / 1440p / 1080p / 720p / ... / 144p` 完整列表
3. **手动切高画质**:选 1080p / 1440p / 2160p(split 路径),mpv 用 `audio-files` 注入 m4a — 在 iOS 上可能更稳(VideoToolbox HW 解码)
4. **字幕**:CC 按钮 → 应见原始语言 + 自动翻译 25 种
5. **PoToken 调试入口**:我的 → 设置 → 关于 → "测试 PoToken + /player (调试)" — 点了应 mint 出 poToken + 列 27 formats

## 已知问题 / 后续

- **首次打开延迟**:第一次启动 BotGuard WebView ~5-10s,后续视频内 1-2s(integrityToken 复用)。可在 app 启动时后台预热。
- **macOS libmpv split 流 audio-files 不稳**:已观察到 1080p 直接选时黑屏。HLS 路径不受影响。iOS / 真机 libmpv 可能不同,需真机验证。
- **integrityToken 6h 过期**:目前在 service 内自动检测,过期会重新 init WebView。
- **字幕翻译**:仅对 `kind=asr` 自动生成轨有效(YT 政策),用户上传字幕翻译会 400。

## 致谢

- TeamNewPipe/NewPipe + NewPipeExtractor — BotGuard 集成参考
- LuanRT/BgUtils — JS BotGuard 实现
- 用户拍板"copy 开源"的方向纠错
