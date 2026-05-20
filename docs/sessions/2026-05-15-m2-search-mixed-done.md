# 2026-05-15 M2 搜索混排完成

> 上级 spec: `docs/specs/multi-source-mvp.md` § M2
> 派活 spec: `docs/specs/m2-search-mixed.md`
> Fix spec: `docs/specs/m2-fix-analyze-errors.md`

## 结果摘要

| 项 | 状态 |
|---|---|
| 新建 4 文件(mixed_search_item / source_badge / yt_search_supplement / yt_video_card_h) | ✅ |
| 改 view.dart (+85/-15) | ✅ |
| `SearchVideoController` 不动 | ✅ 一行都没改 |
| 父类 `SearchPanelController` 不动 | ✅ |
| 任何 hook override 不动 | ✅(grep 验证见下) |
| `flutter analyze` 0 issues | ✅(独立复验) |
| feature flag off 行为回退 | ✅(view.dart 顶层 `if (!kEnableYoutube)` 走旧路径) |

## 改动文件清单

```
A  lib/common/source/mixed_search_item.dart          # MixedSearchItem sealed + mergeMixed
A  lib/common/source/source_badge.dart                # YT 红 / B 站粉 角标 widget
A  lib/services/youtube/yt_search_supplement.dart     # 并列 YT controller + 分页
A  lib/common/widgets/video_card/yt_video_card_h.dart # YT 横向卡片(含 SourceBadge)
M  lib/pages/search_panel/video/view.dart             # initState 注 YT controller / buildList 内混排
```

## Override 链 grep 结果(spec § Step 1 要求)

```
SearchPanelController (父类) — controller.dart
  L80  @override List<T>? getDataList(R response)
  L85  @override bool customHandleResponse(...)
  L116 @override Future<void> onReload()

SearchVideoController (本次目标 child) — video/controller.dart
  L41  @override List<SearchVideoItemModel>? getDataList(...)   ← 用户 vibe 加 SearchFilter 的现场
  L48  @override bool customHandleResponse(...)

SearchAllController — all/controller.dart
  L26  @override List? getDataList(...)
  L31  @override bool customHandleResponse(...)
```

**M2 的实际改动验证**: view.dart 内只调用 `controller.onLoadMore()` / `ytController.onLoadMore()`,**未新增 override,未触碰已有 override**。雷区完全避开。

## 过程教训(归档项目纪律)

1. **workbuddy 第 1 轮 Max turns(50) exceeded**
   - 文件交付完整,但**没自验**,代码不编译
   - `flutter analyze` 报 12 issue(7 error / 2 warning / 3 info)
   - 上级 spec 的"自验步骤"未被 workbuddy 当成硬规则

2. **军师收尾**
   - 用户拍板 B(派 workbuddy 修,不破例代劳)
   - 写 fix spec(精准列 12 issue + 修法 + 行号),派 workbuddy 第 2 轮(effort: high, turns: 25)
   - 第 2 轮 5-8 分钟修完,`No issues found!`,独立复验通过

3. **可记入项目纪律的教训(候选)**:
   - workbuddy 派活 spec 里"必须实跑 analyze 0 issue"的硬要求要更显眼;turns 上限也要给足
   - "未通过自验视作未完成"可以写进 AGENTS.md

## 关键技术决策

### D1: youtube_explode_dart 类型

`yt.search.search(...)` 返回的是 `VideoSearchList`(不是 `SearchList`),元素是 `Video`(不是 `SearchResult`)。`VideoSearchList extends BasePagedList<Video>`,有 `.nextPage() → Future<VideoSearchList?>`。

**M3 / M4 沿用**: 任何 youtube_explode_dart 接口先看 `~/.pub-cache/hosted/pub.dev/youtube_explode_dart-3.1.0/lib/src/` 源码,别凭类名猜。

### D2: 失败降级

YT search 失败时,`state.value = const Success(<YtVideoItem>[])` —— 用空 Success 而非 Error,避免触发 B 站列表跟着报错。**降级原则**: YT 出问题不能拖累 B 站主体验。

### D3: GetX tag 命名

YT controller tag 用 `'yt_${searchType.name}_${tag}'` 区分多个搜索 panel 实例,避免冲突。生命周期跟 view 一致(initState put / dispose delete)。

### D4: 混排策略

`mergeMixed(bili, yt, biliBatch: 10, ytBatch: 5)` — 每 10 条 B 站后插 5 条 YT,轮转直到任一源耗尽,余下追加。**调参口子留在 mergeMixed 参数**,以后用户嫌 YT 太多/太少改这里。

### D5: 卡片视觉

YtVideoCardH 风格对齐 VideoCardH(横向 Row,左封面,右标题+作者+播放量),YT 角标右上角红色。**视觉不追求像素级一致**,过得去即可,真机感受 M3 阶段一并打磨。

## 给 M3 的注意点

1. **详情页路由**: YT 卡片当前 onTap 是 Toast 占位,M3 时改成路由跳详情页,带 `source=yt&videoId=...` query
2. **取流策略**: M0 已确认 muxed 流上限 360p,M3 实做 player 接入时先试 muxed,如不能播再考虑分离流合流(项目用 media_kit,看是否支持 multi-source)
3. **简介字段**: yt_video.dart 还未建,M3 会用到 `yt.videos.get(VideoId)` 拿到 Video 对象,字段比搜索结果更全(描述全文 / 标签 等)
4. **YT 详情页评论 tab**: 占位,但不真调 commentsClient(评论延后到 M4)

## 不在本次

- 真机交互测试(用户晚些自己装到 iPhone 试搜索是否真混排出 YT 结果)
- 视觉打磨
- M3 / M4
