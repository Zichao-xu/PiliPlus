# 2026-05-15 ~ 2026-05-16 M5 详情页打磨 + 登录 bug 修复 (跨日)

> 跨日 session,从 22:00 干到 02:00。

## M5 详情页打磨(对齐 PiliPlus 颗粒度)

新建 `lib/pages/yt_video/yt_video_controls.dart`(~470 行)、改 `yt_video_page.dart` ~200 行,落地内容:

| 项 | 实现 |
|---|---|
| TabBar(简介 / 评论) | StatefulWidget + TabController(2),评论 tab 复用 PiliPlus 的 `HttpError` 空状态 |
| 全屏切换 | SystemChrome 切横屏 + immersiveSticky;`_isFullscreen` 时整屏 only player |
| 标题 marquee | 自写 `_MarqueeText` — TextPainter 测溢出,溢出才滚;短标题左对齐静态 |
| 顶部右侧按钮 | 分享(复制 youtu.be 链接)+ 更多(占位) |
| 中央 → 单击不弹 | 删 `_buildCenterPlayPause`;手势改 L/M/R 三分,M 双击 toggle play |
| 底部 bar 紧凑 | Slider thumb 6→5 / overlay 14→10;Row 锁高 36;padding 收紧 |
| 进度条 fallback | YT 上 `player.stream.duration` 持续 0 → `fallbackDuration` 参数,page 传 `_detail.duration`(yt_explode 元数据) |
| 标题/简介省略 + 展开 | `_expandableText` 用 LayoutBuilder + TextPainter 测溢出,溢出才显示展开/收起 |
| 标签 chip + 收纳 | `_buildTags` 默认显示 6 个,超出 `展开 (N)` |
| 三连占位 | 点赞/点踩/收藏/分享 Row(YT 需登录,Toast 占位) |
| 时长格式 | `mm:ss` / `hh:mm:ss`(原为"xx 分钟") |
| 时间相对显示 | `DateFormatUtils.dateFormat` 跟 B 站完全同格式 |
| 渐进式加载 | 删 spinner,封面图占位 + 顶部 overlay 立即显示,player 后接 |
| **画质切换** | `fetchMuxedStreams` 返回所有 muxed + label;controls 按钮 + sheet;切换保进度 |
| **字幕** | `fetchSubtitleTracks`(yt closedCaptions → VTT URL);`SubtitleTrack.uri` 注入;controls subtitle 按钮 + sheet |

搜索页:
- B 站图标换用户桌面 PNG `assets/images/source_bilibili.png`,size/0.7 抵消透底白边,YT 等大(16)
- 删 B 站三个点菜单(VideoCardH 加 `showMenu` 参数,搜索页传 false)
- 删 SourceBadge 文字版,改图标版,角标移到右下
- 1:1 严格穿插混排(替代 10:5 批次扎堆)
- 排序联动:GetX Worker `ever` 监听 SearchVideoController.loadingState,Success → Loading 时 `ytController.reload()`
- 搜索建议加 YT(`yt.search.getQuerySuggestions`,1:1 交错合并)

设置:
- 4 个"我的"顶栏开关 default_settings.json 由 false → true

未做(物理限制):
- 720p+:YT muxed 上限 360p,720p+ 需 video-only + audio-only 合流,media_kit 不支持(留 ffmpeg 改造 spec)

## 登录 bug 跨日攻关(本节核心教训)

### 用户报告
- 账密/扫码登录后 toast "登录成功",但"我的"页仍游客;动态页能刷,设置-退出可见账号
- 导入登录信息备份也失败

### 错误路径
1. 第一轮:加 mine `onChangeAccount` 时 `queryUserInfo()` 拉刷新 — **没解决根因**
2. 第二轮:智能识别按钮 + setting/account JSON 互导 — **绕开问题**
3. 第三轮:加 diag toast(`DIAG main: ...` / `DIAG cookies: ...` / `DIAG userInfo err: ...`) — 用户没装上诊断
4. 第四轮:改 setAccount 在 fresh 场景自动 set main+heartbeat,绕开 switchAccountDialog — **绕得太狠**
5. 第五轮:`Get.context!` → `Get.overlayContext ?? context` + `useRootNavigator: true` — defensive 但非根因

### 真正根因(用户提示后秒定位)
vibe 加的 `_applyDefaultAccountIfFirstLaunch` 把默认账号塞进 `Accounts.account` box,启动时 `Accounts.refresh()` 用账号 type set 把它绑到 `accountMode[main]`,**`Accounts.main.isLogin` 永远 true**。

setAccount 内 `if (Accounts.main.isLogin)` 走 true 分支 → 仅 toast "登录成功",**不调 switchAccountDialog**,新账号入 box 但 accountMode 不变。

### Fix
- 撤掉 `_applyDefaultAccountIfFirstLaunch`(`accounts.dart`)
- 保留 `_applyDefaultsIfFirstLaunch`(setting 预导入,纯 K/V 无副作用)
- `switchAccountDialog` 用 `Get.overlayContext` 作为 defensive 保留

### 教训(已存 memory `feedback_ask_vibe_diff_first.md`)
**用户 vibe 改过的项目里出现 init/登录/状态 bug,先问用户对上游做过哪些非标改动**。我盲探 4 轮没找到的东西,用户两条提示("0=游客切换窗口没弹"/"对比原版,我预导入配置可能有问题")秒命中。原因:上游初始化代码我读了能看明白单步逻辑,但 vibe 在 init 流里插的 hook 会破坏"全新启动 = 全游客"这种**隐含状态假设**,而这种假设我读单文件读不出。

## Memory 落定(今晚新增 3 条)

1. `feedback_minimal_first.md` — 新依赖/外部接入先隔离环境跑通 POC
2. `feedback_no_local_deadloop.md` — 不挡主线的错误跳过,不钻牛角尖
3. `feedback_ask_vibe_diff_first.md` — vibe 项目 bug 先问用户改动

## IPA 时间线

| 时间 | 版本 | 内容 |
|---|---|---|
| 19:24 | M2 | 搜索混排真机过 |
| 21:23 | M3v2 | 视频详情独立路由真机过 |
| 21:40 | M4 | 评论占位 |
| 22:23-23:40 | M5 v1-v8 | 控件 / 视觉 / 字幕 / 画质 等迭代 8 版 |
| 00:09 | v9 | 设置导入 null guard |
| 00:51 | v10 | 智能识别 + mine queryUserInfo |
| 01:01 | diag | 诊断 toast |
| 01:40 | v11 | setAccount 绕弹窗(后撤) |
| 01:46 | v12 | 默认开关 → true |
| 01:53 | v13 | overlayContext |
| 02:00 | v14 | **撤 default_account 预导入** ← 真根因 |
