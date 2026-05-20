# Spec: 多源 MVP — 接入 YouTube

> 状态: **草稿,待用户过**
> 关联会话: `docs/sessions/2026-05-15-multi-source-kickoff.md`
> 范围: 搜索混排 + YouTube 视频播放 + 简介 + 评论(只读)
> 不在范围: 推荐流、动态、订阅、点赞、收藏、历史、下载、字幕、弹幕、登录、发评论

## 0. 设计原则

1. **不动 B 站现有路径**: YouTube 走平行子目录,不改 `lib/http/`、`lib/grpc/`、`lib/tcp/` 任何文件
2. **抽象层薄**: MVP 不引入"通用 source 接口",直接在 UI 分发点用 `enum VideoSource` 判断;等第三个源出现再抽象
3. **少改上游**: 改动尽量集中在新文件;上游已有文件只做最小必要分发(if/switch)
4. **可一键摘除**: YouTube 出问题时,关一个 feature flag 让搜索 / 详情页退回纯 B 站行为

## 1. 依赖与目录新增

### 1.1 新依赖
```yaml
# pubspec.yaml
dependencies:
  youtube_explode_dart: ^2.x  # 最新稳定版,具体由 M1 阶段确定
```

### 1.2 新目录
```
lib/
  models_new/
    youtube/                  # YouTube 数据模型(平行于 bilibili 各 model)
      yt_video_item.dart
      yt_video_detail.dart
      yt_reply.dart
      yt_reply_page.dart
  services/
    youtube/                  # YouTube 数据通路
      yt_client.dart          # youtube_explode_dart 单例封装
      yt_search.dart          # 搜索
      yt_video.dart           # 视频元信息
      yt_reply.dart           # 评论拉取(只读)
      yt_mapper.dart          # YT model → 项目 unified model 的映射
  common/
    source/
      video_source.dart       # enum VideoSource { bilibili, youtube }
      source_badge.dart       # 卡片角标 widget
  pages/
    search_panel/
      video/
        ... (现有)
      youtube/                # YouTube 搜索结果 panel(M2 决定是否需要独立 panel,见下)
    video/
      introduction/
        local/
        pgc/
        ugc/
        yt/                   # YouTube 视频详情简介模块
          controller.dart
          view.dart
```

### 1.3 feature flag

`lib/build_config.dart` 加一项:
```dart
static const bool kEnableYoutube = true;  // 出问题时改 false 一键回退
```

## 2. 里程碑

### M0 — 独立最小 POC ✅ 已完成 (2026-05-15)

> **2/3 通过**: 搜索 ✅ / 取流 ✅ / 评论 ❌(库 3.1.0 内部 null check,延后到 M4)。详见 `docs/sessions/2026-05-15-yt-poc-done.md`。
> M1 开工依据已锁定: `youtube_explode_dart ^3.1.0`,接口形态见 session log "已确认可用的 API 形态" 段。

<details><summary>原 M0 spec(保留备查)</summary>

#### M0 原始范围

> **必经关卡**: PiliPlus 主工程**不动一行**,先在独立 dart 工程里跑通 youtube_explode_dart 三件事。三件事跑不通就不进 M1。

**目标**: 在 PiliPlus 仓库外独立验证:
1. **搜索**: 关键词 → 视频列表(标题/作者/时长/封面/播放量)
2. **取流**: videoId → 可播放直链 URL(muxed 流够用即可)
3. **取评论**: videoId → 评论列表(作者/内容/时间/点赞数,首屏 + continuation 翻页)

**位置**:
- 独立 dart console 工程: `~/PiliPlus/scratch/yt_poc/`(`scratch/` 加入 `.gitignore` 或保留作参考,见 § 验收)
- 主工程零改动

**改动**(均在 `scratch/yt_poc/` 内):
- `pubspec.yaml` —— 只依赖 `youtube_explode_dart`
- `bin/search.dart` —— print 搜索结果
- `bin/stream.dart` —— print 取流 URL,可选用 `mpv <url>` 在本机播一下验证
- `bin/comments.dart` —— print 评论首屏 + 翻第二页
- `README.md` —— 跑法,踩到的坑

**验收**:
1. 三个脚本能在本机网络下跑出正常输出
2. 取到的流 URL 能用 `mpv` / VLC 实际播放出画面和声音
3. 写一段 ~10 行的 session log: `docs/sessions/2026-05-XX-yt-poc-done.md`,记录: 选用的 youtube_explode_dart 版本、踩到的坑、确认可行的 API 形态、需要带入 M1 的注意点
4. **三件事必须全部跑通**;有一件不通,先在 POC 工程内修,不要进 M1

**派活**: workbuddy 直接干,spec 已经够细。

</details>

---

### M1 — 数据源骨架 (~0.5 day)

**目标**: `youtube_explode_dart` 跑通,能在 dart 命令行 / 单元测试里搜出第一条 YouTube 视频。

**改动**:
- `pubspec.yaml` 加依赖
- `lib/common/source/video_source.dart` —— enum
- `lib/services/youtube/yt_client.dart` —— `YoutubeExplode` 单例 + dispose
- `lib/services/youtube/yt_search.dart` —— `searchVideos(keyword) → List<YtVideoItem>`
- `lib/models_new/youtube/yt_video_item.dart` —— 字段对齐 `SearchVideoItemModel` 子集: id / title / author / thumbnail / duration / viewCount / publishDate
- `test/youtube/yt_search_test.dart` —— 网络冒烟测试(可选 skip)

**验收**: `flutter test test/youtube/yt_search_test.dart` 通过,或在 dev 工具脚本里能 print 出搜索结果。

---

### M2 — 搜索混排 (~1-1.5 day)

**目标**: 在 PiliPlus 搜索结果"视频"标签页里,B 站结果与 YouTube 结果**混排**,卡片右上角带来源角标。

**设计选择**:
- **不新增独立 YouTube panel**,而是在现有 `search_panel/video/` 里做合并
- 触发并行请求: B 站搜索 + YouTube 搜索,各自返回后合并、按某种简单策略交叉(MVP 用 "B 站 N 条 + YouTube M 条 + B 站 N 条 + ..." 轮询交错,N=10,M=5)
- 分页: B 站走原分页,YouTube 走 `youtube_explode_dart` 的 continuation token;两边各自维护翻页状态

**改动清单**:
- `lib/pages/search_panel/video/controller.dart` —— 注入并行的 YT 搜索,合并到 `loadingState`
- `lib/pages/search_panel/video/view.dart` —— item 渲染处加 source 判断,YT item 走新 widget
- `lib/common/source/source_badge.dart` —— 角标(YT 红色 / B 站粉色)
- `lib/services/youtube/yt_search.dart` —— 增加分页支持
- `lib/models_new/youtube/yt_video_item.dart` —— 若 M1 字段不全,这里补
- 一个新的卡片 widget(目录待定,跟现有视频卡放一起): `youtube_search_video_card.dart`

**验收**:
1. 在搜索框搜常用关键词(中英文各 1),结果列表里能看见两种来源,角标清晰
2. 滚动到底能继续翻页,两源各自延续
3. `kEnableYoutube = false` 时,搜索行为与上游完全一致(无残留)
4. YouTube 请求失败不影响 B 站结果展示(降级用 toast/日志)

---

### M3 — YouTube 视频详情:播放器 + 简介 (~1-2 day) — ✅ **完成于 M3v2**(独立路由路线)。M3v1 沿用 isFileSource 失败,详见 `docs/sessions/2026-05-15-m3-grayed.md` + `2026-05-15-m3v2-done.md`

**目标**: 点击搜索结果里的 YouTube 卡片,进入视频详情页,能播,能看简介。

**路由**:
- 复用现有视频详情页路由,但 query 参数加 `source=yt&videoId=<ytId>`
- 详情页根 controller 在 init 时识别 source,分发到 yt 分支

**改动清单**:
- `lib/router/` —— 详情路由参数扩展(尽量不增新路由,只加 query 参数)
- `lib/pages/video/detail/controller.dart`(具体文件名以现有为准) —— 加 source 分发
- `lib/pages/video/introduction/yt/controller.dart` + `view.dart` —— 新模块,渲染 YT 视频简介
- `lib/services/youtube/yt_video.dart` —— `fetchVideo(id) → YtVideoDetail` + 取直链流 URL(优先 muxed,fallback 选最高画质 video-only + audio-only 合流;具体策略在 M3 实现时定)
- 播放器接入: 复用项目现有 player widget,只换数据源 URL(YouTube 不需要弹幕层)

**风险点**:
- iOS 上 YouTube 部分视频会要求 `n` / `sig` 解密 —— `youtube_explode_dart` 已内置,出问题时再处理
- 分离流(video-only + audio-only)在现有 player 上能不能播 —— **若不能,MVP 阶段只取 muxed 流(画质封顶 360p/720p),够用即可**;高画质留到下一版

**验收**:
1. 从搜索结果点开 YT 视频能播,音视频同步
2. 简介区显示: 标题 / 频道名 / 发布时间 / 播放量 / 描述全文
3. 不显示任何"点赞 / 收藏 / 投币 / 分享 / 三连"按钮(YT 上下文里这些不存在)
4. 横竖屏切换、退出、再进 不崩

---

### M4 — YouTube 评论区(只读) (~1 day) — 🟡 **占位完成**,等上游库 fix 接真数据。详见 `docs/sessions/2026-05-15-m4-placeholder.md` ⚠️ 已知风险

> **依赖问题**: M0 验证发现 `youtube_explode_dart 3.1.0` 评论 API 在 `_Comment._commentRenderer:141` null check 崩溃。所有视频复现。
> **开工前必做**: 单独起一份调研 spec,选项: 锁老版本 / 换替代库 / 提 PR / 自实现 InnerTube 调用。详见 `docs/sessions/2026-05-15-yt-poc-done.md`。
> M1/M2/M3 完成前 **不开 M4**。

**目标**: 视频详情页评论 tab 能显示 YouTube 评论,支持加载更多;不做"发评论 / 点赞评论 / 回复评论"。

**改动清单**:
- `lib/services/youtube/yt_reply.dart` —— `fetchComments(videoId, continuation?) → YtReplyPage`
- `lib/models_new/youtube/yt_reply.dart`、`yt_reply_page.dart`
- 评论 tab 分发: 现有评论模块在 source==yt 时,走 YT 评论 controller(具体文件待 M4 时勘察)
- 二级回复(reply-to-reply): MVP **不展开**,只显示一级评论 + "N 条回复" 静态计数;展开留到下一版

**验收**:
1. 详情页评论 tab 能显示前 20 条评论(作者头像 / 名字 / 内容 / 时间 / 点赞数)
2. 滚到底能加载更多
3. B 站视频的评论行为完全不变

## 3. 不做什么(防止 scope creep)

- ❌ YouTube 登录态
- ❌ YouTube 订阅源
- ❌ YouTube 字幕(MVP 没字幕,后续单独 spec)
- ❌ 弹幕(YouTube 无弹幕)
- ❌ 把 YouTube 视频塞进 B 站推荐流 / 动态 / 历史
- ❌ 跨源点赞 / 收藏聚合
- ❌ 通用 source 抽象接口(留到接第三个源时再抽)

## 4. 排期与派活

| 里程碑 | 估时 | 类型 | 适合派给 |
|---|---|---|---|
| **M0 独立 POC** | **0.5d** | **隔离工程,验证依赖可用** | **workbuddy** |
| M1 数据源骨架 | 0.5d | 进主工程,新文件 + 接 POC 验证过的 API | workbuddy |
| M2 搜索混排 | 1-1.5d | 改上游文件 + 新 widget | workbuddy(改动点列清楚),军师把关 |
| M3 视频详情 | 1-2d | 涉及播放器路径,要试 | 军师起手,workbuddy 接细节 |
| M4 评论只读 | 1d | 模式重复 M3 | workbuddy |

**纪律**: M0 跑不通,M1 不开工。新依赖、新外部 API 一律先 POC,再进主工程 —— 已写入 AI 跨项目 memory。

每个里程碑做完写一份 `docs/sessions/YYYY-MM-DD-<milestone>.md`,记决策、坑、改动文件清单。

## 5. 待用户确认

- [ ] 接入策略 / MVP 范围 / 实现方式(本 spec § 0-1)
- [ ] 混排策略(轮询交错 10 B 站 + 5 YT,可调)
- [ ] 画质策略: MVP 接受 muxed 流封顶 360p/720p,够用即可
- [ ] 评论二级回复 MVP 不展开
- [ ] 排期与派活倾向

用户过完上面 5 条,我就把 M1 拆成 workbuddy 派活 spec,启动开干。
