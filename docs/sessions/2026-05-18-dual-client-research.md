# 2026-05-18 双 client 热备 + YT 反爬现状深度调研

## 用户原始需求

接 cookie → 让 YT 视频能播 → 调研时效性 → 双 client(ANDROID_VR + MWEB)热备,不要 self-host VPS

## 调研结论(3 个 agent 并行)

### Yattee(用户 mac 上装着)
**完全不走原生 Innertube**。`InvidiousAPI.swift` / `PipedAPI.swift` / `PeerTubeAPI.swift` 三个后端,自己零 Innertube 代码。Cookie 只对 invidious 实例自身 login,绝不对 google.com。**Yattee 对我们没参考价值**(它不解 YT 反爬,外包给 iv-org `invidious-companion`)。
- 关键源:[InvidiousAPI.swift:249](https://github.com/yattee/yattee/blob/main/Model/Applications/InvidiousAPI.swift#L249)
- 拒绝 built-in extractor:[yattee#165](https://github.com/yattee/yattee/issues/165#issuecomment-2283517637)

### yt-dlp `_INNERTUBE_CLIENTS` 表(决定性证据)
| client | SUPPORTS_COOKIES |
|---|---|
| web, web_safari, web_embedded, web_music, mweb, tv | ✅ |
| **ios, android, tv_simply, android_vr** | 🔴 **False** |

**IOS client 永远 LOGIN_REQUIRED 是设计**,不是 bug。文件:[yt_dlp/extractor/youtube/_base.py](https://github.com/yt-dlp/yt-dlp/blob/master/yt_dlp/extractor/youtube/_base.py)。

### 时效性(决定性 ✗)

- **ANDROID_VR 已经在塌**:yt-dlp [#15865](https://github.com/yt-dlp/yt-dlp/issues/15865) 2026-04 报"全部公开视频要求登录,android_vr LOGIN_REQUIRED",yt-dlp [#16150](https://github.com/yt-dlp/yt-dlp/issues/16150) 2026-03 "android_vr 变 erratic,只返 360p"。**预期寿命 1-4 周**。
- **WEB+cookie 单独失效**:必须配 BotGuard PoToken,且要解 player.js 拿 signatureTimestamp。8h+ 实现。
- **Invidious public instance 只剩 4 个**(invidious.nerdvpn.de / inv.nadeko.net / inv.thepixora.com / yt.chocolatemoo53.com)。Piped ~15 个。**self-host 才稳**,但用户拒绝 VPS。

### Dart 生态(决定性 ✗)
**30+ Flutter YT/YT-Music 项目里找不到一个"cookie 登录 + youtube.com Innertube /player 拿 1080p"的成功实现**。youtube_explode_dart 的 cookie injection 不是公开 API(issue [#341](https://github.com/Hexer10/youtube_explode_dart/issues/341)),maintainer Coronon 已经预告会迁到 yt-dlp 代理([#363](https://github.com/Hexer10/youtube_explode_dart/issues/363))。

## 本次实施(用户决策:AB 都做,不要 VPS)

### Spec
`docs/specs/yt-dual-client-failover.md` — ANDROID_VR + MWEB 热备 + yt_explode 兜底

### 改动
1. **[lib/services/youtube/yt_innertube_player.dart](../../lib/services/youtube/yt_innertube_player.dart)**:
   - 弃用 IOS client
   - 加 `enum YtInnertubeClient { androidVr, mweb }`
   - `fetchPlayer(videoId, client: ...)` 按 client 切 context.client + UA + auth 策略
   - ANDROID_VR 不传 cookie,MWEB 全套 auth(Cookie + SAPISIDHASH + X-Origin)
2. **[lib/services/youtube/yt_video.dart::fetchMuxedStreams](../../lib/services/youtube/yt_video.dart)**:
   - 热备链:`ANDROID_VR → MWEB(登录态)→ yt_explode 兜底`
   - 错误展示 `[1] [2] [3]` 三段诊断
3. **yt_explode `_streamClients`**: `androidVr` + `safari` (WEB+cipher) + `mweb` 优先

## macOS Debug 自测(2026-05-18,本机 IP)

| 路径 | 结果 |
|---|---|
| 未登录 + ANDROID_VR | 🔴 LOGIN_REQUIRED("Sign in to confirm you're not a bot")|
| 登录 + MWEB | 🔴 DioException HTTP 400 (Cookie+SAPISIDHASH+IOS-UA-likely combination issue) |
| 登录 + yt_explode | 🔴 VideoUnplayableException, LOGIN_REQUIRED |

**Mac 上这条 IP 出口已被 YT 反爬全面打到** —— 不是代码问题,是 YT 当下对 mac IP 做了限制(可能是 datacenter range 或我们短时间多次试探后 throttle)。

**三段错误诊断 UI 工作完美 ✓**:
```
取流失败
[1] ANDROID_VR: /player playabilityStatus=LOGIN_REQUIRED reason=Sign in to confirm you're not a bot
[2] MWEB: DioException [bad response]: HTTP 400 ...
[3] yt_explode: VideoUnplayableException: Video '0Uhh62MUEic' is unplayable.
```

## 交付

- iOS Release IPA:`~/Desktop/PiliPlus-dual-client-2026-05-18.ipa`(23MB,TrollStore 装)

## 真机验收方向

**这个 IPA 装手机后行为可能完全不同**:
- 手机蜂窝 / WiFi 不同出口 IP,可能没被 YT 反爬打过 → ANDROID_VR 可能直接 work
- iOS 真机 UA + IP 组合 server 信任度可能高于 Mac
- 即使 ANDROID_VR 还塌,MWEB 在不同 IP 上 HTTP 400 可能消失

## 已知风险(诚实告知)

1. **本周 ANDROID_VR 高概率全网塌**(yt-dlp #15865 指标);需要应急方案 — 唯一长寿是 WEB+解 player.js+BotGuard 或 invidious-companion
2. **MWEB HTTP 400 根因**未在 mac 实证(可能是 mac 出口 IP / 可能是 SAPISIDHASH origin 配置)
3. **三段诊断错误是当前最大价值** — 真机失败用户能给我看完整 chain,下次改更精准

## 未完事项

- 解 player.js + signatureTimestamp + n-sig + BotGuard 完整 WEB 路径(8h+ 重写)
- 真机验证 + 错误信息回报后微调
- 自动重试 / 错误时引导用户切换登录态 / 切换 client UI
- 错误页加返回按钮(`_buildPlayerArea` error state 现没渲染 topbar)

## 工作纪律新增 memory

[快速变动领域先核查时效性](../../../../.claude/projects/-Users-adams/memory/feedback_check_recency_first.md) — 反爬/平台政策这类月更月变,推方案前先 web search 30 天证据,给"预期寿命"
