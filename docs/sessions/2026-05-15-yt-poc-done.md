# 2026-05-15 M0 YouTube POC 验收

> 上级 spec: `docs/specs/multi-source-mvp.md` § M0
> 派活 spec: `docs/specs/m0-yt-poc.md`
> POC 工程: `scratch/yt_poc/`(`.gitignore` 已忽略)

## 结果摘要

| 项 | 状态 |
|---|---|
| 搜索 `search.dart` | ✅ |
| 取流 `stream.dart` | ✅ (muxed 上限 360p,高画质需合流) |
| 评论 `comments.dart` | ❌ 库内部 null check 崩溃,**延后到 M4 排查** |
| 文档 README | ✅(军师补,workbuddy 第一轮没补全) |
| 文档 session log | ✅(本文) |

**结论**: M0 视为通过(2/3 + 风险登记)。开 M1。

## 已确认可用的 API 形态(M1 直接照搬)

```dart
final yt = YoutubeExplode();

// 搜索
final results = await yt.search.search(keyword);
// 字段: video.id.value / video.title / video.author / video.duration / video.thumbnails / video.viewCount(可能为 null)

// 取流
final video = await yt.videos.get(VideoId(videoId));
final manifest = await yt.videos.streamsClient.getManifest(videoId);
// manifest.muxed / manifest.audioOnly / manifest.videoOnly
// 每条 stream 有: tag / videoQuality / container.name / bitrate / url

yt.close();  // 必调
```

## 派活过程

- workbuddy 用 `kimi-k2.6 + xhigh + turns 30` 派出
- 触发 `Max turns (30) exceeded`,文件已建但 README / session log / 自测均缺
- 军师补全文档 + 实跑三脚本验收(不属于"动手写代码",属于规格 + 验收范畴)
- workbuddy 失败计数: M0 阶段 = 1(还未触发"两次失败下场"安全阀)

## 重要决策

### D1: youtube_explode_dart 版本

spec 写的 `^2.x` 不存在,workbuddy 选了 `^3.1.0`(实测可用),纳入主工程也用此版本起步。**记**: 上级 spec 该处应改成 "pub.dev 最新稳定版"。

### D2: 评论崩溃如何处置

不在 M1/M2/M3 路径上,**不修不查**,登记到 README 风险段。M4 开工前再起一次孤立调研。依据: AI memory `feedback_no_local_deadloop.md`。

### D3: 画质上限

muxed 流封顶 360p (itag 18) 是 YT 的硬约束。MVP 阶段就用 muxed 360p,够日常看。后续优化路径 = 合流(video-only + audio-only),交给现有 player 看能否吃分离流,M3 实做时再决。

## 给 M1 的注意点

1. `youtube_explode_dart` 用 `^3.1.0`,起手就锁版本(spec 里写明)
2. 必须 `yt.close()`,在 GetX controller 的 `onClose` 调
3. 单例 vs 每次 new: M1 spec 里要明确 — 推荐 service 层全局单例,避免重复 init token
4. 搜索分页用 `nextPage()` 拿后续,M2 实做时确认其等价物
5. M1 不要碰评论,接口形态可以预留 stub,但 commentsClient 别真调
6. 流 URL 有 expire 参数,几小时后失效 — 不要缓存 URL 自身,缓存 `videoId` 重新换

## 不在本次

- M4 评论 API 重排查 — 留到 M4 单独 session
- 高画质 muxed 缺失的合流方案 — M3 实做时决
