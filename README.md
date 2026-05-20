<div align="center">
    <img width="160" height="160" src="assets/images/logo/logo.png">
    <h1>PiliPlus &mdash; Multi-source fork</h1>
    <p>
        <a href="#english">English</a> · <a href="#%E4%B8%AD%E6%96%87">中文</a>
    </p>
    <p>
        <a href="https://github.com/bggRGjQaUbCoE/PiliPlus">upstream</a> ·
        <a href="docs/">docs/</a> ·
        <a href="AGENTS.md">AGENTS.md</a>
    </p>
</div>

> **This is a personal fork of [bggRGjQaUbCoE/PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus)** that adds **YouTube as a second video source** alongside Bilibili. Primary target is iOS via TrollStore (no codesign). The credit for the original Bilibili client, the UI, and 99% of the code goes to the upstream author and contributors.
>
> 本仓库是 [bggRGjQaUbCoE/PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus) 的**个人 fork**,在原 Bilibili 客户端基础上**接入 YouTube 作为第二视频源**。主目标是 iOS via TrollStore(免签名侧载)。原项目的功劳归上游作者和贡献者。

---

<a id="english"></a>

## What this fork adds on top of upstream

The upstream PiliPlus is a complete Bilibili client. This fork keeps everything upstream does, and **layers a YouTube source on top of the same search / detail / comment / player surface**. Below is a complete diff of behavior — anything not listed here is upstream behavior.

### New: YouTube as a second video source

- **Mixed search**: type a query once, get Bilibili and YouTube results in a single result list (red badge marks YouTube items)
- **YouTube video detail page** (`lib/pages/yt_video/`): independent page that does not reuse the Bilibili `VideoDetailController` / `PlPlayer`. Uses `media_kit` (mpv) directly
- **YouTube comments**: top-level comments fetched via Innertube `/next` endpoint (bypasses `youtube_explode_dart`'s broken comment client). Supports continuation pagination
- **YouTube reply (write)**: short-tap "Reply" button on each comment → dialog → POST `/youtubei/v1/comment/create_comment_reply`. Reply token is mined from `commentEntityPayload` by deep-walking the response for `createCommentReplyEndpoint.params`
- **Like / dislike / remove rating** (`yt_like_service.dart`): writes via SAPISIDHASH auth (currently returns 401 on some networks — need browser-captured headers to align, work in progress)

### YouTube authentication

- **WebView Google sign-in** (`lib/pages/yt_login/`) — wraps Google's OAuth flow, harvests `SAPISID` / `SID` / `LOGIN_INFO` / `__Secure-*PSID*` cookies on success
- **SAPISIDHASH signer** (`lib/utils/yt_auth.dart`) — `SHA1("${ts}_${SAPISID}_${origin}")` per Google's internal convention. Used as `Authorization: SAPISIDHASH <ts>_<hash>` for Innertube private endpoints
- **Account export / import** — both Bilibili and YouTube cookies can be exported to a single JSON and re-imported on another device

### YouTube stream pipeline

The stream layer is the messy part — YouTube's anti-bot is what it is.

- **Three-stage hot-backup chain** in `fetchMuxedStreams`:
  1. Innertube + `ANDROID_VR` client (no-login default path)
  2. Innertube + `MWEB` (logged-in fallback)
  3. `youtube_explode_dart` (`androidVr/safari/mweb/android/androidSdkless/ios/tv`) — last resort, returns 360p muxed only
- **PoToken** (`yt_potoken_service.dart`) — local WebView with `BotGuard` to mint a PoToken, unlocking 1080p+ from Innertube
- **HLS master URL preferred** when client returns it — mpv handles ABR / audio-video sync internally, the most reliable high-quality path
- **Split streams** (video-only + audio-only) configured when only DASH is available: collected as `YtMuxedStreamOption.audioUrl`. mpv's `audio-add ... select` is dispatched after `player.stream.duration` is ready (otherwise the command is silent-dropped before demuxer is up — the root cause of "high-quality streams have no sound" on early builds)
- **mpv tuning for split streams**: 32 MB buffer, `cache-secs=60`, `demuxer-readahead-secs=30`, `cache-pause-wait=0.5`, `audio-pts-correction-threshold=0.05`, `framedrop=vo`. Starts 1-3 s slower than upstream but stays in sync with two HTTP streams
- **Cookie + UA injection into mpv** via `setMediaHeader`, so the googlevideo CDN doesn't 403 on logged-in / split URLs

### YouTube subtitles

- All native captions listed (Chinese pinned first, then non-auto-generated, then alphabetical)
- **Auto-translation to 25 common target languages** via YouTube's own `timedtext?tlang=` server-side translation — no extra API call

### YouTube metadata translation

- **MyMemory** (`yt_translate_service.dart`) — anonymous, no API key, 1000 chars/day/IP
- Heuristic source-language detection: ASCII → en, hiragana/katakana → ja, Hangul → ko, CJK → zh-CN
- Long-text chunker: splits text >400 chars on sentence terminators / newlines before sending (avoids MyMemory's 414 URI Too Long)
- Translatable: title, description, tags, every comment

### Settings panel

New `YouTube` section in settings: default video quality (auto/HLS / 1080p / 720p / 360p), default subtitle mode (off / native / translate), translate target language, auto-translate metadata toggle.

### Other

- `lib/common/source/mixed_search_item.dart` — search result polymorphism (Bilibili + YouTube items in one feed)
- `assets/config/default_settings.json` — opinionated defaults baked in (dark theme, AVC1 decoder preference, expanded buffer, sponsor-block, etc.)
- TrollStore-friendly build flags in `ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme`

### Removed / changed from upstream

- Nothing visibly removed — the YouTube source is purely additive; if you don't sign into YouTube, the app behaves like upstream.

### Building

```bash
flutter pub get
flutter build ios --release --no-codesign   # IPA → TrollStore
flutter build macos --release               # native test target
```

`.fvmrc` pins the Flutter version. Recent dev was on Flutter 3.41.9 / Dart 3.11.5.

### Known limitations

- **YouTube anti-bot is moving target**. Streams / comments / reply token paths can break any time YouTube rotates their `Innertube` response schema. Hot-backup chain absorbs most cases; if everything breaks, ship a session log.
- **`like` API returns 401** on some networks. Pending browser-captured headers to align.
- **Audio-video sync on split streams** depends on network quality. 1080p HLS (if the client returns `hlsManifestUrl`) is rock-solid; DASH split is buffering-dependent.
- Bilibili side is **untouched** — upstream is the source of truth.

### Documentation

Per-decision context lives in:

- [`AGENTS.md`](AGENTS.md) — collaboration conventions for AI agents working on this repo
- [`docs/specs/`](docs/specs/) — implementation specs (one per feature / fix before code)
- [`docs/sessions/`](docs/sessions/) — chronological session logs (one per significant change)

### License

Same as upstream. See upstream's [LICENSE](LICENSE).

### Credits

Original PiliPlus by [@bggRGjQaUbCoE](https://github.com/bggRGjQaUbCoE) and upstream contributors. YouTube source layer in this fork: [@Zichao-xu](https://github.com/Zichao-xu) (this repo).

---

<a id="中文"></a>

## 这个 fork 相比上游加了什么

上游 [bggRGjQaUbCoE/PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus) 是一个完整的 Bilibili 客户端。本 fork 保留它的全部功能,**在同一套"搜索 / 详情 / 评论 / 播放器"界面上再叠一层 YouTube 视频源**。下面是行为 diff —— **没在这里列出的全部 = 上游行为**。

### 新增:YouTube 第二视频源

- **混排搜索**:一个搜索框同时给出 B 站和 YouTube 结果(YT 项右下角红色徽标)
- **YouTube 视频详情页**(`lib/pages/yt_video/`):独立 page,**不复用** Bilibili 的 `VideoDetailController` / `PlPlayer`,直接走 `media_kit`(mpv 内核)
- **YouTube 评论**:走 Innertube `/next` 接口拿顶层评论(绕开 `youtube_explode_dart` 在 YT 新 ViewModel 结构下崩 null check 的 commentsClient),续页正常
- **YouTube 评论回复**:每条评论 footer 短按"回复"→ dialog → POST `/youtubei/v1/comment/create_comment_reply`。回复 token 从响应里**深度遍历挖** `createCommentReplyEndpoint.params`
- **点赞 / 点踩 / 取消**(`yt_like_service.dart`):走 SAPISIDHASH 鉴权(部分网络仍返回 401,需要浏览器抓包对齐 header,WIP)

### YouTube 登录

- **WebView Google 登录**(`lib/pages/yt_login/`)—— 包 Google OAuth 流程,登录成功后采集 `SAPISID` / `SID` / `LOGIN_INFO` / `__Secure-*PSID*` 等 cookies
- **SAPISIDHASH 签名**(`lib/utils/yt_auth.dart`)—— `SHA1("${ts}_${SAPISID}_${origin}")`,Google 内部约定。用于 Innertube 私享接口的 `Authorization: SAPISIDHASH <ts>_<hash>` header
- **账号导入导出** —— B 站和 YouTube 的 cookies 可一并导出到单个 JSON,在别的设备上一键导入

### YouTube 流管线

流这一层是反爬战场,逻辑相对乱。

- **`fetchMuxedStreams` 三段热备链**:
  1. Innertube + `ANDROID_VR` 客户端(免登录主路径)
  2. Innertube + `MWEB`(登录态兜底)
  3. `youtube_explode_dart`(`androidVr/safari/mweb/android/androidSdkless/ios/tv`)—— 最后兜底,只能拿 360p muxed
- **PoToken**(`yt_potoken_service.dart`)—— 本地 WebView 跑 `BotGuard` 出 PoToken,解锁 Innertube 的 1080p+
- **优先 HLS master URL**(如果客户端返回)—— mpv 内部处理 ABR 和音视频同步,高画质最稳的路径
- **Split 双流**(video-only + audio-only)—— 仅 DASH 可用时收集为 `YtMuxedStreamOption.audioUrl`。mpv 的 `audio-add ... select` 在 `player.stream.duration` ready 后才发(早期版本"高清无声"的真根因就是 demuxer 还没起就发了命令,被 silent drop)
- **mpv split 流调优**:32MB buffer / `cache-secs=60` / `demuxer-readahead-secs=30` / `cache-pause-wait=0.5` / `audio-pts-correction-threshold=0.05` / `framedrop=vo`。起播比上游慢 1-3 秒换 split 双流的同步稳定
- **Cookie + UA 注入 mpv**(`setMediaHeader`)—— 让 googlevideo CDN 在登录态 / split URL 上不 403

### YouTube 字幕

- 列出所有原生字幕(中文置顶,然后非自动生成,然后字母序)
- **自动翻译到 25 种常用目标语言** —— 走 YouTube 自家 `timedtext?tlang=` 服务端翻译,无需额外 API

### YouTube 元数据翻译

- **MyMemory**(`yt_translate_service.dart`)—— 匿名免 API key,1000 字/天/IP
- 启发式源语言识别:全 ASCII → en,假名 → ja,Hangul → ko,CJK → zh-CN
- 长文本切片:>400 字符按句末标点 / 换行切片后逐段发(避开 MyMemory 的 414 URI Too Long)
- 可翻译范围:标题、简介、标签、每条评论

### 设置面板

新增 `YouTube` 区:默认画质(自动 HLS / 1080p / 720p / 360p)、默认字幕模式(关 / 原文 / 翻译)、翻译目标语言、是否自动翻译元数据。

### 其他

- `lib/common/source/mixed_search_item.dart` —— 搜索结果多态(B 站 + YouTube 同列)
- `assets/config/default_settings.json` —— 烤进去的默认偏好(深色、AVC1 解码、扩展缓冲、SponsorBlock 等)
- `ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme` —— TrollStore 友好的 build flag

### 相比上游的删除 / 修改

- 没有可见删除 —— YouTube 源**纯叠加**,不登录 YT 时 app 行为完全等于上游。

### 构建

```bash
flutter pub get
flutter build ios --release --no-codesign   # 出 IPA → TrollStore
flutter build macos --release               # 原生测试目标
```

`.fvmrc` 锁 Flutter 版本。近期开发用的是 Flutter 3.41.9 / Dart 3.11.5。

### 已知限制

- **YouTube 反爬月更月变**。流 / 评论 / 回复 token 路径在 YT 改 Innertube 响应结构时随时可能挂。三段热备链能吸收大部分情况;真全挂请提 issue 带 session log
- **`like` API 部分网络 401**。等浏览器抓包对齐 header
- **Split 双流音画同步**靠网络。1080p HLS(客户端返回 `hlsManifestUrl` 时)非常稳;DASH split 看缓冲
- **B 站侧完全不动** —— 上游是 source of truth

### 文档

每个决策的上下文留在仓库里:

- [`AGENTS.md`](AGENTS.md) —— 本仓库 AI agent 协作约定
- [`docs/specs/`](docs/specs/) —— 实施 spec(代码改之前先写)
- [`docs/sessions/`](docs/sessions/) —— 时序的会话日志(每次重要改动一份)

### 许可

与上游一致,见仓库 [LICENSE](LICENSE)。

### 致谢

原 PiliPlus 由 [@bggRGjQaUbCoE](https://github.com/bggRGjQaUbCoE) 及上游贡献者开发。本 fork 的 YouTube 源层:[@Zichao-xu](https://github.com/Zichao-xu)。
