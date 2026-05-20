# 2026-05-19 Phase A 4 项完成(缓冲条 / cookie 合并 / 设置面板 / DeepL 翻译)

## 用户决策

7 项优化分两 Phase 实施(详见 `2026-05-18-state-checkpoint.md`)。Phase A 4 项今天一气做完。Phase B 3 项(自动画质/点赞踩/评论回复)等切回 dual-client + 反爬过再做。

Phase A 顺序按"由简到复杂"打:#2 缓冲条 → #4 cookie 合并导出 → #5 设置面板 → #6 翻译。翻译 API 选 **DeepL Free**(500K 字/月免费)。

## 改动

### #2 进度条加缓冲条

[yt_video_controls.dart](../../lib/pages/yt_video/yt_video_controls.dart):
- 加 `_buffer` state + 订阅 `player.stream.buffer`(media_kit `demuxer-cache-time`)
- 进度条用 Stack 叠加:Slider(active=白)+ 一层白 alpha 50% 显示已缓冲范围
- Spec:[yt-buffer-bar.md](../specs/yt-buffer-bar.md)

### #4 关于页"导入/导出登录信息"合并 YT

[about/view.dart:319](../../lib/pages/about/view.dart):
- 新 JSON schema:`{"bilibili": {...}, "youtube": {yt_auth_cookies, yt_auth_user_name, yt_auth_avatar_url, yt_auth_channel_id}}`
- 兼容旧格式:无 `bilibili`/`youtube` 顶层 key → 按旧 B 站格式 fallback
- Spec:[yt-merge-login-export.md](../specs/yt-merge-login-export.md)

### #5 YouTube 设置面板

新增:
- [yt_setting.dart](../../lib/pages/setting/yt_setting.dart) — 设置 page
- `SettingType.ytSetting` 枚举值 [setting_type.dart](../../lib/models/common/setting_type.dart)
- 路由 `/ytSetting` [app_pages.dart](../../lib/router/app_pages.dart)
- 设置 page 入口 [setting/view.dart](../../lib/pages/setting/view.dart)
- storage keys 在 [storage_key.dart](../../lib/utils/storage_key.dart) `SettingBoxKey` ytXxx 段

设置项:
- **播放** — 默认画质(auto/360p/720p/1080p,目前 only 360p 实际生效)
- **字幕** — 默认字幕(off/native/translate)+ 翻译目标语言(若 translate)
- **翻译** — 自动翻译开关 / 翻译目标语言(DeepL 风格 ZH-HANS/EN/JA/...)/ 服务商(DeepL Free or Pro)/ API Key

### #6 翻译(标题 / 简介 / Tag)

新增:
- [yt_translate_service.dart](../../lib/services/youtube/yt_translate_service.dart) — DeepL API client + 内存缓存(单例,`translate` 单段 + `translateMany` 批量,内存 cache key="targetLang|sourceText")
- [yt_translatable_text.dart](../../lib/common/widgets/yt_translatable_text.dart) — X 风格 wrapper widget,显示原文/译文 + 切换按钮 + `autoTranslate` flag(自动翻译开关传入)

接入 [yt_video_page.dart::_buildIntro](../../lib/pages/yt_video/yt_video_page.dart):
- 标题:`YtTranslatableText`
- 简介:`YtTranslatableText`(maxLines + "展开" 按钮)
- Tag:批量翻译 + "翻译标签" / "显示原文" 切换按钮

## 不在本轮(下轮做)

- **评论翻译 + 评论回复**:留到 Phase B,跟 #7 评论回复一起做(都改 yt_comments_view)
- **设置项实际生效逻辑**:
  - 默认画质 `auto`/`360p` 现在不影响实际行为(yt_explode 360p only)
  - 默认字幕设置不影响 `_setSubtitle` 自动选择逻辑(目前固定优先 zh)
  - 这两条等切回 dual-client + 翻译流接入后再 wire
- **DeepL 自动翻译开关** 已经在 widget level 接好,但 video 页其他文本(简介 vs 标题)是否分别开关、tag 是否走 auto,等用户实测反馈再调

## 风险 / 已知

- DeepL Free 注册需要绑信用卡(免费 quota 500K 字/月 + 0 信用卡扣费,但要 KYC)
- 翻译走代理:DeepL API endpoint `api-free.deepl.com` 在国内不稳。**用户当前节点能访问就 OK,否则要切节点**(同 YT 反爬,这是网络层问题)
- 翻译失败时弹 toast,不影响视频正常播放 — fail-soft

## 交付

- iOS Release IPA:`~/Desktop/PiliPlus-phaseA-2026-05-19.ipa`(23MB,无签名,TrollStore 装)

## 真机验收清单

1. **#2 缓冲条**:任意视频点 ▶ 起播 → 进度条应能看到 3 层(灰白底 / 半透白已缓冲 / 实白当前位置 / thumb)
2. **#4 cookie 合并导出**:设置 → 关于 → "导入/导出登录信息" → 导出 → JSON 应含 `bilibili` + `youtube` 两段
3. **#4 导入兼容旧**:粘贴老格式(只有 B 站 mid → LoginAccount map)→ 仍能 import B 站不报错
4. **#5 设置面板**:设置 → "YouTube 设置" → 看到画质 / 字幕 / 翻译三段 + DeepL API Key 输入
5. **#5 输入 API Key**:粘 DeepL Free API key → 保存 → 重新进设置 → 显示 `xxxxxx***`(脱敏)
6. **#6 翻译**:
   - 设 API Key 后,YT 视频页 → 标题下应有 "翻译" 按钮(蓝色小字)
   - 点 → 标题变译文 + 下方 "显示原文 / DeepL" 字样
   - 简介同样
   - tags 区有 "翻译标签" 按钮,点击 batch translate

## 未完事项

- Phase B(切回 dual-client 后):#1 自动画质 + #3 点赞踩 + #7 评论回复 + 评论翻译,捆绑做
- 设置项接入实际播放/翻译逻辑(默认画质 / 默认字幕 / 自动翻译应用范围)
