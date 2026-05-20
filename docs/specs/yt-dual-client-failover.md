# YT 双 client 热备 — ANDROID_VR + MWEB

> 调研结论(2026-05-18):
> - **IOS client + cookie 永远 LOGIN_REQUIRED**(yt-dlp 标 `SUPPORTS_COOKIES=False`)
> - **ANDROID_VR + poToken** 在 yt-dlp / NewPipe 是当前主流免登录路径,1-4 周高危但 today 可用
> - **MWEB client** 在 yt-dlp 标 `SUPPORTS_COOKIES=True`,配 cookie + GVS poToken 可走
> - **WEB client + 解 player.js** 工作量 8h+,本轮**不做**,放下一轮
> - **不要 self-host invidious-companion**(用户决定不要 VPS)
>
> 本 spec 实现 **AB 双路径热备**:免登录用 ANDROID_VR,登录后用 MWEB,**任意一路失败 fallback 到另一路**。
> 都失败再 fallback 旧的 yt_explode 360p,最坏出错误页。

## 目标

1. 用户**不登录**也能播放 YT 视频(主路径 ANDROID_VR + poToken)
2. 用户**登录后**走 MWEB + cookie,稳定性更好,且画质菜单含 720p / 1080p split 流
3. **热备**:A 失败自动尝试 B,B 失败再 yt_explode,任何一条出结果 UI 就活了

## 改动

### 1. `lib/services/youtube/yt_innertube_player.dart`

- 新增 `enum YtInnertubeClient { androidVr, mweb }`,默认 `androidVr`
- 把现有 `_iosClientVersion / _iosUa` 等常量挪到 `_AndroidVrConfig` / `_MwebConfig`,按 client 选用
- ANDROID_VR 关键参数(参 yt-dlp `_INNERTUBE_CLIENTS`):
  ```
  clientName: 'ANDROID_VR'
  clientVersion: '1.61.48'
  deviceMake: 'Oculus'
  deviceModel: 'Quest 3'
  androidSdkVersion: 32
  osName: 'Android'
  osVersion: '12L'
  userAgent: 'com.google.android.apps.youtube.vr.oculus/1.61.48 (Linux; U; Android 12L; en_US) gzip'
  ```
- MWEB 关键参数:
  ```
  clientName: 'MWEB'
  clientVersion: '2.20260101.00.00'(取 yt-dlp dev 同步)
  userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 ...'
  ```
- `fetchPlayer(videoId, client: YtInnertubeClient)`:按 client 走对应 config + auth header 策略
  - ANDROID_VR: poToken 必备,cookie 不传(server 不认)
  - MWEB: cookie 必传,poToken 仍带(GVS poToken)
- 移除当前 retry-without-poToken 逻辑(没必要 — 真挂了上层 fallback 别的 client)

### 2. `lib/services/youtube/yt_video.dart::fetchMuxedStreams`

新 chain:
```
1. ANDROID_VR (无 cookie + poToken)
   ↓ 失败
2. MWEB(若 isLoggedIn 才走,带 cookie + poToken)
   ↓ 失败/未登录
3. yt_explode_dart 360p 兜底
   ↓ 失败
   throw 双层错误(同现有)
```

每个 client 超时 25s。错误信息分段累计:
```
取流失败
[1] ANDROID_VR: <err1>
[2] MWEB: <err2 或 跳过(未登录)>
[3] yt_explode: <err3>
```

### 3. `lib/pages/yt_video/yt_video_page.dart::_startPlayback`

- 已经有 setMediaHeader cookie 注入。**保留**,但提示:实际上 stream URL 自带 `&pot=` poToken,cookie 主要给 MWEB stream / split 高画质 URL 加成

### 4. yt_explode `_streamClients`(`yt_video.dart::_streamClients`)

把第一位从 `android` 改为 `androidVr` 等价。验证 youtube_explode_dart 是否有 `YoutubeApiClient.androidVr` 枚举。

## 不做(本轮)

- 不实现 WEB client + signatureTimestamp 解 player.js 路径(8h+,下一轮 spec)
- 不接 invidious-companion(用户拒绝 VPS)
- 不改点赞/评论 write API(下一轮)

## 风险 + 时效性

- yt-dlp #15865(2026-04):ANDROID_VR 报 LOGIN_REQUIRED — **1-4 周内可能整条挂**
- yt-dlp PO-Token Guide:MWEB 需要 GVS poToken,Player poToken 可不要 — 我们目前 mint 的是 Player poToken,可能 MWEB 不认。需要验证
- 真挂的兜底:回到 cookie 粘贴 + 提示用户"YT 反爬升级,等下一轮 WEB 路径"

## 验收

1. **未登录**进任意 YT 视频 → 点 ▶ → 走 ANDROID_VR → **应该出画**(360p+),不再 LOGIN_REQUIRED
2. **登录后**(粘贴 cookie)同视频 → 走 MWEB → 出画 + 画质菜单含 720p/1080p
3. **双路径都失败时**错误页含 `[1] [2] [3]` 三段诊断

## 交付

- macOS Debug 自测:免登录 + 登录后两条都跑一遍
- iOS Release IPA:`~/Desktop/PiliPlus-dual-client-2026-05-18.ipa`
