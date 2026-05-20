# 2026-05-15 多源接入启动会

> 决定接入 YouTube 作为第二视频源,锁 MVP 范围,选实现路线。

## 背景

桌面上有两份 v0 草稿: `piliplus_multi_source_proposal_v0.md`(本项目)和 `bhx_proposal_v0.md`(X 客户端净化,另起项目)。本次会话只处理 PiliPlus 这边,BHX 暂搁。

## 摸底结论

PiliPlus 现状没有"数据源"抽象层 —— `lib/http`、`lib/grpc`、`lib/tcp` 全按 B 站协议绑死。"复用播放器和 UI" 在 widget 层成立,但**搜索 / 视频 / 评论的数据通路得新开一条 YouTube 分支并在 UI 层做 source 分发**。

可复用的接入位置:
- `lib/pages/search_panel/{all,video,article,live,pgc,user}/` —— 已是按类型分子目录,新增 `youtube/` 子目录天然适配
- `lib/pages/video/introduction/{local,pgc,ugc}/` —— 已有 source 分发雏形,新增 `yt/` 并列
- 评论区入口在 `lib/pages/main_reply/` 和 `lib/pages/video/reply_new/`,需要在分发层判断 source

## 决策

### 接入策略
**选 C++**(C 的搜索 MVP + 把视频详情页的"简介 + 评论"也算进 MVP):
- 搜索页 B 站 + YouTube 结果**混排**,卡片带来源角标
- 点击 YouTube 卡片 → 视频详情页,只渲染 **播放器 + 简介 + 评论** 三块
- 推荐流 / 动态 / 订阅 / 搜索 trending 等暂不接 YouTube

### YouTube 功能范围
- ✅ 视频播放
- ✅ 简介(标题 / 描述 / 频道名 / 时长 / 发布时间 / 播放量)
- ✅ 评论区(只读,MVP 不做发评论)
- ❌ 点赞 / 收藏 / 订阅 / 历史 / 下载 / 字幕 / 弹幕(后续视需要再加,不在 MVP)

### 过滤阈值
**共用一套**: 短视频时长 / 最大播放量 / 屏蔽关键词 等阈值跨源生效,MVP 阶段不增设置项。等用户体感不对再升 "共用 + per-source 覆盖"。

### 数据来源
**InnerTube via `youtube_explode_dart`**:
- 无 API key、无配额、无服务器
- 与项目逆向 B 站 API 的价值观一致
- 风险: YouTube 改协议时会坏,届时再修
- 不选官方 Data API(配额过紧,搜索 100 units/次,日上限 100 次)
- 不选 Piped/Invidious(需要服务器或依赖公共实例)

### 服务器
**不需要**。视频流是 YouTube CDN 直链,客户端直拉。未来 SponsorBlock / 翻译字幕 等增值能力再议。

## 工程纪律(用户补充)

**最小化先验证,再进主工程**: 新依赖 / 新外部 API 一律先在隔离工程跑通最小 POC,再进 PiliPlus 主仓库加板块。已记入跨项目 memory(`feedback_minimal_first.md`),今后所有项目都遵守。

对应 spec 里多加了一个 **M0 阶段**: 在 `scratch/yt_poc/` 独立 dart 工程跑通 youtube_explode_dart 的搜索 / 取流 / 取评论三件事。M0 跑不通不开 M1。

## 下一步

1. 起草 `docs/specs/multi-source-mvp.md`(本会话内完成,含 M0 POC 关卡)
2. 用户过 spec 后,优先派 workbuddy 干 M0
3. M0 验收通过后,再启动 M1 主工程改动

## 不在本次范围

- BHX/BHTwitter 项目: 待 PiliPlus MVP 对齐后再启动
- YouTube 登录态(看私享 / 订阅源等): MVP 后再议
- 多账号管理: 暂沿用 B 站现有账号体系,YouTube 不登录
