# 2026-05-19 Phase B 反馈 fix

## 用户反馈对照

| # | 反馈 | 根因 | 修法 |
|---|---|---|---|
| 1 | 没有自动切换 | yt_explode 兜底没 HLS,要 dual-client + 好节点 | 代码无 bug,留 doc 提示 |
| 2 | ✅ 缓冲条 | — | — |
| 3 | 按不动 | `_actionBtn` 用 InkWell,缺 Material 父级 hit-test 失败 | InkWell → `GestureDetector(behavior: opaque)`,padding 略增 |
| 4 | ✅ cookie 导入导出 | — | user 提供 account.json 供后续测试 |
| 5 | ✅ 设置面板 | — | — |
| 6 | ❓ 不要 API key | DeepL Free 也得注册 | 换 **MyMemory** anonymous(免 key,1000 字/天/IP),加启发式源语言识别(en/ja/ko/zh-CN)|
| 7 | 短按不是长按 + reply HTTP 400 | (a) UX 应短按 (b) `createReplyParams=commentId` 是 placeholder | (a) 改"回复"按钮放点赞数旁,短按触发 (b) 真 token 提取下轮做,先友好错误提示 |

## 改动

### #3 fix
[yt_video_page.dart::_actionBtn](../../lib/pages/yt_video/yt_video_page.dart):
- `InkWell` → `GestureDetector(behavior: HitTestBehavior.opaque)`
- `padding vertical 4 → 6`(扩大热区)

### #6 翻译换 MyMemory
[yt_translate_service.dart](../../lib/services/youtube/yt_translate_service.dart):
- 完全重写,走 `https://api.mymemory.translated.net/get`
- **匿名**,无需注册/API key
- 启发式源语言:ASCII → en;hiragana/katakana → ja;Hangul → ko;CJK 汉字 → zh-CN
- 源==目标时直接返回原文(省额度)
- 内存缓存(同段文本只调一次)
- 单 IP 1000 字/天免费;超额度 fail-soft

设置面板 [yt_setting.dart](../../lib/pages/setting/yt_setting.dart):
- 删 "翻译服务商" 选项 / 删 "DeepL API Key" 输入框
- 改成静态提示「MyMemory anonymous,免 key,1000 字/天/IP」

dart 实测 ✓:
```
en|zh-CN  "Never Gonna Give You Up" → "永不放弃"
en|zh-CN  长简介 → "Rick Astley的《Never Gonna Give You Up》官方视频"
zh-CN|en  "你好世界" → "Hello world"
```

### #7 短按
[yt_comments_view.dart](../../lib/pages/yt_video/yt_comments_view.dart):
- 删长按 sheet
- 评论 footer(点赞数那行)加 **"回复"** 短按按钮(蓝字 + reply icon),`GestureDetector behavior:opaque`
- 错误处理:`INVALID_ARGUMENT` 时 toast "回复 API 暂不可用(YT 反爬 reply token 待对接)" — 不让用户看难懂的英文 stack

### #7 剩余(下一轮)
- `YtComment` 加 `createReplyParams` 字段
- `yt_comments.dart::_parsePage` 遍历响应 JSON,挖 `createCommentReplyEndpoint.params` 关联到 commentId
- `createReply` body 用真 token 而非 commentId

## 交付

- iOS Release IPA(TrollStore 装):`~/Desktop/PiliPlus-phaseB-fixes-2026-05-19.ipa`(23MB)

## 真机验收清单

1. **#3 点赞**:进 YT 视频 → 简介下 "点赞" 按钮 → 短按 → toast "已点赞" / 图标变实心蓝;再点取消
2. **#6 翻译**:进 YT 视频 → 标题/简介下 "翻译" 按钮 → 直接 work(无需 API key)。Toast 可能报"超额度"(每天 1000 字 / IP)
3. **#7 回复**:评论 footer "回复" 按钮 → 短按 → 弹 dialog → 输入 → 发送。**仍预期 INVALID_ARGUMENT**,toast 友好提示。真 token 下轮做

## #1 自动画质说明(代码无 bug)

`_pickInitialQualityIdx` 已经按 `ytDefaultQuality` 选流。但 mac/真机 节点拿不到 dual-client(ANDROID_VR/MWEB)stream 时,fallback yt_explode 只返 360p 单流,**没有 HLS 选项可选**,所以不切换。

要真 ABR 无缝:
- 节点必须好,YT 反爬不拦
- ANDROID_VR 调 InnerTube `/player` 返回 `hlsManifestUrl`
- `_innertubeToMuxedOptions` 已经把 HLS 加在 streams 第一位
- `_pickInitialQualityIdx` 'auto' 时优先选

满足后 mpv 自动 ABR。**当前 mac 拿不到 = 节点+反爬层问题,不是代码层 bug**。
