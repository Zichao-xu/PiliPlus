# 2026-05-18 状态 checkpoint — 360p 兜底 vs dual-client 切换

## 真机实测确认

- **`PiliPlus-dual-client-2026-05-18.ipa` (22:34)**:真机切节点后**可以用**,ANDROID_VR/MWEB 双 client 热备链 work。用户拍板**下次继续改 YT 时从这个版本起步**。
- **`PiliPlus-360p-fallback-2026-05-18.ipa` (22:58)**:当前 working tree 状态 == 这个 IPA。妥协方案,只走 yt_explode 360p。**留作保底**。

## 当前 working tree 是什么状态

**360p fallback**。已撤掉 Innertube + cookie + 双 client 路径,但 `yt_innertube_player.dart` / `yt_potoken_service.dart` / `_innertubeToMuxedOptions` / `YtAuthService` 代码全留着,不需要重写。

## 下次想恢复 dual-client,改这 4 处即可

### 1. `lib/services/youtube/yt_video.dart::fetchMuxedStreams`

当前(360p 兜底):
```dart
Future<List<YtMuxedStreamOption>> fetchMuxedStreams(String videoId) async {
  Object? lastErr;
  for (var attempt = 0; attempt < 2; attempt++) {
    try {
      final out = await _fetchMuxedOnce(videoId);
      if (out.isNotEmpty) return out;
    } catch (e) {
      lastErr = e;
      if (attempt == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
  }
  throw Exception('取流失败\nyt_explode: $lastErr');
}
```

切回 dual-client:换成 `ANDROID_VR → MWEB(登录态) → yt_explode 三段` 热备链,**完整代码参考 docs/sessions/2026-05-18-dual-client-research.md** 里的实施段。

### 2. `lib/services/youtube/yt_video.dart::_streamClients`

当前(360p):
```dart
static final _streamClients = [
  YoutubeApiClient.android,
  YoutubeApiClient.androidSdkless,
  YoutubeApiClient.ios,
  YoutubeApiClient.tv,
];
```

切回 dual-client:把 `androidVr` / `safari` / `mweb` 加到最前面:
```dart
static final _streamClients = [
  YoutubeApiClient.androidVr,
  YoutubeApiClient.safari,
  YoutubeApiClient.mweb,
  YoutubeApiClient.android,
  YoutubeApiClient.androidSdkless,
  YoutubeApiClient.ios,
  YoutubeApiClient.tv,
];
```

### 3. `lib/services/youtube/yt_video.dart::_fetchMuxedOnce`

当前(360p):
```dart
const authEnabled = false;
// ignore: dead_code
if (authEnabled) {
```

切回 dual-client:
```dart
final authEnabled = YtAuthService.isLoggedIn;
if (authEnabled) {
```
(同时把上方 `import 'package:PiliPlus/utils/yt_auth.dart'` 的 `ignore: unused_import` 标记去掉)

### 4. `lib/pages/yt_video/yt_video_page.dart::_startPlayback` 中 `player.setMediaHeader`

当前(360p):
```dart
player.setMediaHeader(
  userAgent: '...iPhone...Safari...',
);
```

切回 dual-client:回到带 Cookie header 的版本:
```dart
final ytCookies = YtAuthService.cookies;
final cookieHeader = (ytCookies != null && ytCookies.isNotEmpty)
    ? ytCookies.entries.map((e) => '${e.key}=${e.value}').join('; ')
    : null;
player.setMediaHeader(
  userAgent: '...iPhone...Safari...',
  headers: cookieHeader != null ? {'Cookie': cookieHeader} : null,
);
```
(同时把 `lib/pages/yt_video/yt_video_page.dart` 顶部确保 `import 'package:PiliPlus/utils/yt_auth.dart';`)

## 不需要动的(都在仓库里)

- `lib/services/youtube/yt_innertube_player.dart` — `YtInnertubeClient.androidVr / mweb` enum + 完整 `_fetchPlayerOnce` 实现
- `lib/services/youtube/yt_potoken_service.dart` — BotGuard WebView 实现
- `lib/utils/yt_auth.dart` — `YtAuthService.cookies / buildAuthHeaders / saveCookies`
- `lib/pages/yt_login/yt_login_page.dart` — cookie 粘贴登录 UI
- `assets/yt/po_token.html` — NewPipe BotGuard runner
- `scratch/inject_yt_cookie.dart` + `scratch/clear_yt_cookie.dart` + `/tmp/decrypt_dia_cookies.py` — 测试用 cookie 工具

## 当时推 dual-client 的几个补丁(可选,有时间再做)

- MWEB context 完整对齐 yt-dlp(已经加了 deviceMake/deviceModel/osName/osVersion,但 SAPISIDHASH 在 mac 触发 HTTP 400,要么 only-Cookie 要么对齐 yt-dlp web 路径)
- 错误页加返回按钮(`_buildPlayerError` 状态无 topbar)
- 登录态切高画质 split 流的成功率验证(需要登录 cookie + 节点都对的真机)

## 节点 / 反爬经验小记

- mac 这条 IP 连续 50+ 次 PoToken/cookie 试探后被全网 LOGIN_REQUIRED。**等冷却**或**换节点**都能恢复
- 看 [feedback_change_node_before_code.md](../../../../.claude/projects/-Users-adams/memory/feedback_change_node_before_code.md) — 反爬出问题先换节点不要先动代码
