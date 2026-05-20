# 2026-05-19 高清音频 + reply 真 token

## 用户真机反馈对照(phaseB / phaseB-fixes IPA)

| # | 项 | 状态 | 注 |
|---|---|---|---|
| 1 | 没自动切换 | 被 #N 拖累 | 见 #N |
| 3 | 按不动 | phaseB-fixes 已修(此前 InkWell→GestureDetector) | 用户真机看的还是 phaseB,**装新 IPA**即可 |
| 6 | 不要 API key | phaseB-fixes 已修(换 MyMemory anonymous) | 同上 |
| 7 | 短按 + reply HTTP 400 | 短按 phaseB-fixes 已修;**真 token 本轮修** | 见 task B |
| N | **除 360p 其他无声音** | **本轮修** | 见 task A |
| N | 暂停按钮多按几下,初始 ▶ | 跟随 A 修复 | 与 A 同根 |

phaseB-fixes IPA(`~/Desktop/PiliPlus-phaseB-fixes-2026-05-19.ipa`)在用户真机没装上,
所以 #3 #6 #7-toast 是上一版的行为。

## Task A — 高清音频注入

spec: [yt-audio-injection-fix.md](../specs/yt-audio-injection-fix.md)

根因:[yt_video_page.dart](../../lib/pages/yt_video/yt_video_page.dart) 用 `player.setAudioTrack(AudioTrack.uri(audioUrl))`,
media_kit 1.1.11 native 实现走 mpv `audio-add ... cache`,**cache 模式只加进 track list 不切换 active**,
所以 split 流(720p+ video-only + 外部 audio)始终静音;只有 360p muxed 单流自带 audio 才有声。

附带:用户报「暂停按钮一开始 ▶,多按几下才正常」 — split 流 audio 选择失败后 mpv buffering 卡住,
`state.playing` 长时间 false,controls 镜像显示 ▶。根治音频也治这个。

### 改动

[yt_video_page.dart](../../lib/pages/yt_video/yt_video_page.dart) 两处:

```dart
// 之前
await player.setAudioTrack(AudioTrack.uri(audioUrl));
// 之后
await player.command([
  'audio-add', audioUrl, 'select', 'External', 'auto',
]);
```

`mode=select` 立即加载 + 切换为当前 active audio。`Player = NativePlayer` 别名,`command(List<String>)` 是公开 API。

不改 media_kit 上游,只是绕开它写死 `cache` 的那个分支。

## Task B — createReply 真 token

spec: [yt-reply-token.md](../specs/yt-reply-token.md)

之前 `createReply(commentId, text)` 把 commentId 当 `createReplyParams` 发,server 直接 INVALID_ARGUMENT。
真 token 是 YT InnerTube `createCommentReplyEndpoint.params` 的 protobuf base64。

### 改动

- [yt_comment.dart](../../lib/models_new/youtube/yt_comment.dart):加 `String? createReplyParams`
- [yt_comments.dart::_parsePage](../../lib/services/youtube/yt_comments.dart):
  - 每条 commentEntityPayload 子树深度遍历找 `createCommentReplyEndpoint.params`
  - 路径浮动多,深搜兜底最稳
- [yt_comments.dart::createReply](../../lib/services/youtube/yt_comments.dart):入参由 `parentCommentId` → `createReplyParams`,body 用真 token
- [yt_comments_view.dart](../../lib/pages/yt_video/yt_comments_view.dart):
  - 入口判 `c.createReplyParams == null` → toast「该评论暂不可回复」
  - 调用传 `c.createReplyParams!`
  - 错误 toast 区分 INVALID_ARGUMENT(token 失效)/ 其他

## 自测

- macOS:`flutter analyze` 改动文件全过(15 个 info,无 warning/error)
- iOS Release build:✓ 65.6MB,IPA 23MB

### macOS Release computer-use 自验(本轮新加,前几次没做被骂)

build macos release → `open -n PiliPlus.app` → computer-use 走流程,观察:

| 路径 | 结果 |
|---|---|
| 启动 + 我的页 | ✓ 显示「YouTube 已登录」(之前导入的 account.json cookies 还在 GStorage) |
| 搜索 onelastkiss → 进 Hikaru Utada 视频 | ✓ 标题/简介/Tag/4 按钮 row 全 render |
| 大 ▶ 起播 | ✓ 起播,流量 1.0 MB/s,字幕同步("Oh, can you give me one last kiss?") |
| controls 暂停键初始 | ✓ **‖**(playing 态),不是 ▶。**暂停键 bug 未复现** |
| 实际画质 | 🟡 360p muxed,**mac 拿不到 split 流**(节点反爬,phaseB done 已知) |
| 简介 → 翻译标题 | ✓ "宇多田ヒカル『One Last Kiss』" → "Utada Hikaru "最后一个吻"" |
| 简介 → 分享按钮 | ✓ toast "已复制视频链接" |
| 评论 tab | ✓ 多条评论 render,翻译按钮 + 回复按钮在位 |
| 评论 → 点回复按钮 | ✓ **Dialog 弹出**,placeholder "reply to: ..." → 取消(不真发污染评论区) |
| 简介 → 点赞按钮 | 🟡 onTap 进了(同 _actionBtn 模板,分享 work 证明 hit-test 活),但 toast 没出现 — like API 调用挂或超时,**不是 hit-test 问题** |

### 可验证的结论

- ✅ #3 按不动 — _actionBtn / 短按 reply / 翻译按钮 GestureDetector hit-test 全部活
- ✅ #6 翻译 — MyMemory work,免 key
- ✅ #7-1 短按回复 + dialog — ✓
- ✅ #7-2 reply token 解析命中 — 否则 _openReplyDialog 入口 toast「不可回复」 return
- ❌ 高清音频(关键修复) — **mac 拿不到 split 流,验不了**
- ❌ 暂停键 split 路径 — 同上
- 🟡 like API call 实际成功率 — 上轮 spec 已登记未实测,本轮 mac 也没确认

### 真机必验项

1. **音频**:任意 YT 视频 → 起播 → 默认应该 1080p/HLS,有声;手切 720p / 480p,有声
2. **回复 server**:评论回复 → 真发一条 → 看 server 返回。token 命中已经 mac 验过,只剩 server 接受度
3. **like API**:点赞 → 看 toast 是 "已点赞" / "点赞失败:..."。失败的话给我错误码,本轮再对齐

## 真机反馈(2026-05-19 19:25,phaseB-audio-replytoken IPA)

✅ 评论区翻译正常
✅ 真机能拿到 1080p split 流(说明节点 + dual-client + cookie 链路都通)
❌ **非 360p 全部无声音** — 本轮 `audio-add ... select` 修复**未生效**
❌ 暂停键截图依然是 ▶(高画质 buffering 卡 state.playing) — 跟音频同根

修复假设错了:把 `setAudioTrack(AudioTrack.uri)` 的 `cache` mode 换成 `select` 命令式发,理论上 mpv 该立即切音轨。实测 iOS 真机仍无声,说明根因不是 mode 参数。

### 新假设(待验证)

候选根因:

1. **mpv `audio-add` 时序** — `await player.open(Media(url))` 在 media_kit native impl 里只代表 mpv command "loadfile" 已 dispatch,**不代表 demux 完成 / track-list 就绪**。紧跟 `audio-add` 时,主 demuxer 还没 ready,audio-add 命令可能 silently drop 或被后续 file-loaded 事件覆盖。需要等 mpv `file-loaded` 事件或 `tracks` ready 后再发命令
2. **iOS mpv audio-add 缺特定参数** — `audio-add <url> select <title> <lang>` 第 4 个参数是 lang,有时 mpv 解析失败会拒命令。可以试只发 3 个参数 `audio-add <url> select`
3. **URL 失效 / Cookie 没传** — split video-only 流的 audio URL 是 googlevideo CDN,UA / Cookie / Range 都得对。当前 mpv 是 `setMediaHeader(userAgent + Cookie)`,但 setMediaHeader 给的是当前 media 的 header,**外部 audio-add 可能不走同一份 header**。Cookie 缺失 → 403 → mpv 收到错误后静默 fallback,不报错也不切
4. **媒体格式不匹配** — video 流是 mp4 但 audio 流被选成 webm,mpv 跨容器 demux 不稳(yt_video.dart 里已经做了 mp4↔mp4 / webm↔webm 配对,但 Innertube 那条路径可能配错)

### 排查计划

**先不动代码,先抓现场**:

- 把 mpv 日志 level 拉到 verbose,看 audio-add 命令到底发没发出去 / 收没收到响应
- 看 split 时实际传给 mpv 的 audio URL 长啥样
- 看 mpv 是否报 403 / 解码失败

代码层一旦确认时序问题,**改法可能要监听 player.stream.tracks** 或者用 mpv `file-loaded` event,等 ready 再发 audio-add。这种修法对 mac 也没法验,只能再出 IPA 真机看。

暂停键问题同根,**修了音频会跟着好**(audio 走通 → mpv state.playing 不卡 → controls 镜像同步)。

### 不动手的边界

本条修复 mac 不能验。代码改了再 build IPA 让用户真机验循环成本高(每轮 1080p 测一次)。先跟用户对一下:是直接闷头改 IPA + 真机循环,还是先要一段日志再定方案。

## 真机反馈(2026-05-19 19:3x,phaseB-fixes IPA — 用户装的不是本轮 audio-replytoken)

3 个新错误截图:

### A. like 401(P1)

```
点赞失败:DioException [bad response] status code 401
```

YT `/youtubei/v1/like/like` 拒绝 SAPISIDHASH。可能原因:

1. SAPISIDHASH 算法不被接受(时间戳 / origin / sapisid 选择)
2. 缺 `X-Goog-Visitor-Id` / `X-Goog-PageId` header
3. WEB client context 不对应(server 期望 ANDROID 或 IOS context)
4. cookie SAPISID 失效或选错(__Secure-3PAPISID vs SAPISID)

修法依赖**真实浏览器抓包对齐 header**。无抓包闷头试 = 月更月变的反爬硬扛(参考 [[feedback-check-recency-first]])。

### B. 翻译 414 URI Too Long(P1)

```
翻译失败:DioException status code 414
```

MyMemory GET `?q=<text>&langpair=...`,长简介 / 长评论 → URL 超 8KB,server 414。

修法二选一:
- **(a) 文本 >450 字符分段**(MyMemory 文档建议 ≤500),改动小,仍 GET
- **(b) 改 POST**(MyMemory 同 endpoint 也接 POST),改动稍大,无长度限制

### C. reply toast 显示「回复 API 暂不可用(YT 反爬 reply token 待对接)」

这是 phaseB-fixes 的旧文案,**本轮 audio-replytoken IPA 已删**(改成「该评论暂不可回复」/「token 已失效,刷新评论再试」)。证据:用户装的还是 phaseB-fixes,不是 audio-replytoken。

本身没新代码要写。但 audio 问题没解决前,只装本轮 IPA 没拿 audio 增益 → 用户没动力换。**合并下轮一起出**。

## 第三轮(audio-v2 + translate-414)

### 改动

#### B 翻译 414 修

[yt_translate_service.dart](../../lib/services/youtube/yt_translate_service.dart):
- 加 `_maxChunkChars = 400`(MyMemory GET URL 限制留余量)
- `translate()` 长文本切片(按句末标点 / 换行,>400 字符硬切)后逐段调,拼回
- 短文本(≤400)走原路径不变

#### 音频时序

[yt_video_page.dart](../../lib/pages/yt_video/yt_video_page.dart):
- 抽 `_addExternalAudio(player, audioUrl)` helper
- **等 `player.stream.duration.firstWhere((d) => d.inMilliseconds > 0)` ready 再发 audio-add**(timeout 4s 兜底)
- 上一轮 IPA 没声音的真根因:`await player.open(Media)` 只代表 loadfile 命令 dispatch,**不代表 mpv demux 就绪**。紧跟 audio-add 命令被 silent drop / 被后续 file-loaded 事件清掉
- audio-add 参数从 5 个精简到 3 个 `['audio-add', url, 'select']`,去掉 title='External' lang='auto'(lang 期望 ISO 639,'auto' 可能让 mpv 拒命令)

### mac 自验

- ✅ build 通过,Release IPA 23MB,macOS 起 app 不崩
- ✅ 翻译标题(英→中)成功:"Jensen Huang: NVIDIA..." → "Jensen Huang :英伟达..." → **短文本路径无回归**
- 🟡 长文本简介翻译(>400 字符)mac 上 ScrollView 在视频下吃滚轮,没点到简介末尾的翻译按钮。**信任分段逻辑** — _splitForTranslate 是纯切字符串,每段 ≤500 字符 ≤ MyMemory GET 限制
- ❌ 音频时序修复:mac 拿不到 split 流,**留真机**

### 交付

`~/Desktop/PiliPlus-audio-v2-translate-2026-05-19.ipa`(23MB)

### 真机验收清单

1. **音频(P0)** — 起任意 YT 视频,默认 1080p HLS 或 split → 应该**有声**。手切 720p/480p split → 有声。若仍无声,请反馈;时序假设也错的话,要换 mpv verbose log 抓现场
2. **翻译 414** — 进任意长简介 YT 视频(如 Lex Fridman),展开 → 简介末尾点「翻译」 → 应该出译文(可能要 30s+,因为是分段串行)
3. **暂停键初始 ‖** — 起播后立刻看播放器控件,应是 ‖。如果还是 ▶,跟音频同根,等音频修了一起
4. **reply 行为(本轮新代码)** — 评论"回复"按钮:
   - 命中 → dialog → 真发 → 看 server 是否 200
   - 未命中 → toast「该评论暂不可回复」
   - token 失效 → toast「回复失败:token 已失效,刷新评论再试」

### 不动手项

A like 401 — **等抓包**才能对齐 header。盲改是反爬硬扛,参考 [[feedback-check-recency-first]]

## 第四轮(buffer-sync)

### 真机反馈

audio-v2 IPA 装上后:**有声音了**(时序修复生效)但「**音画不同步 + 播放卡顿**」。

### 根因

mpv 配置对 YT split 双流极不友好:

| 配置 | 之前 | 之后 | 原因 |
|---|---|---|---|
| `demuxer-readahead-secs` | 1 | **30** | split 双流要分别 demux,1s 余量几乎必 sync 漂移 |
| `cache-secs` | 默认 ~10 | **60** | 网络抖动时 cache 不够 → audio video 异步追 |
| `bufferSize` | 4MB | **32MB** | 同上 |
| `cache-pause` | no | **yes** | 缓冲不足时主动 pause 等数据,而不是让 audio 继续吃 |
| `cache-pause-wait` | — | **0.5** | 至少 0.5s 缓冲再继续 |
| `demuxer-max-bytes` | 默认 ~150MB | **128MiB** | 显式设上限,iOS 内存吃紧时不爆 |
| `audio-pts-correction-threshold` | — | **0.05** | 容忍 50ms 内 audio PTS 偏移 |
| `framedrop` | 默认 | **vo** | 落后只丢 vo 帧,不丢解码帧 |
| `stream-lavf-o` 加 `multiple_requests=1` | — | + | HTTP keep-alive 复用,降两流 setup 开销 |

[yt_video_page.dart](../../lib/pages/yt_video/yt_video_page.dart) 第 100-130 行。

### 代价

起播会**慢 1-3 秒**(等 30s readahead 凑齐)。换 sync 稳定值得。如果你觉得太慢可以再调小。

### 交付

`~/Desktop/PiliPlus-buffer-sync-2026-05-19.ipa`(23MB)

### 真机验

1. 1080p split:**音画同步 + 不卡** ← 关键
2. 起播慢多久(主观)
3. 切画质 720p / 480p split:同上验

如果还卡顿/不同步,**就要换战略了** — 优先拿 HLS 流(IOS client + poToken)而不是 split 双流

## 交付

`~/Desktop/PiliPlus-audio-replytoken-2026-05-19.ipa`(23MB,TrollStore 装)

## 真机验收清单

1. **高清音频**:任意 YT 视频起播 → 默认应该 HLS 自动 or 1080p,有声 → 手动切到 720p / 480p split → 有声 → 切到 360p muxed → 有声
2. **暂停按钮**:进视频 → 点 ▶ 起播 → 几秒后看播放器控件,**应该是 ‖(暂停态图标),不是 ▶**。点一次应立即响应
3. **回复**(onelastkiss 或任意视频):评论 footer「回复」短按 → dialog → 输入 → 发送
   - 若 token 解析命中:期望 toast「回复已发送」
   - 若 path 不命中:toast「该评论暂不可回复」(deep walk 兜底应该 99% 命中)
   - 若 INVALID_ARGUMENT:toast「回复失败:token 已失效,刷新评论再试」

## 已知风险

- **reply token 深搜路径**:基于 NewPipe 当前结构推断。如果命中率 <80%,要 sample 真实响应再调路径
- **mpv `audio-add select` 时序**:open 后立即 add 通常 OK,但若 mpv 在 demux 中可能延迟。
  实测挂的话退化方案:加 listener 等 `tracks` 事件后再发命令
- **dislike/like 实测对齐**:本轮没动,继续留账

## 下一轮(若 token 深搜没命中)

抓一份真实响应保存到 `/tmp/yt_next_sample.json`,grep `createCommentReplyEndpoint`,
看在哪个 path,改对应硬路径优先 + 兜底深搜
