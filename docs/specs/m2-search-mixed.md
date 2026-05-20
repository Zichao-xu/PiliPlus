# Spec: M2 — 搜索结果 B 站 + YouTube 混排

> 状态: **派活中**
> 上级 spec: `docs/specs/multi-source-mvp.md` § M2
> 前置: M1 已完成,见 `docs/sessions/2026-05-15-m1-yt-skeleton-done.md`
> 执行: workbuddy (`kimi-k2.6 + xhigh`)

## 目标

搜索"视频"标签页里:
- B 站结果与 YouTube 结果**在同一个 grid 里混排**
- 每条 YouTube 卡片右上角带 "YouTube" 角标
- 滚到底两源各自翻页
- `BuildConfig.kEnableYoutube = false` 时行为与 M1 之前完全一致(零回归)

## 关键设计原则(读懂再动手)

### ⚠️ 必读 — Override 雷区警告

`SearchVideoController` 已经 override 了父类的 `getDataList` 和 `customHandleResponse`。本次 spec **绝对禁止**动这两个 hook,因为:
1. 它们承载着用户自己加的 `SearchFilter` 过滤逻辑
2. 之前已经发生过"父类改了 child 没调 super"的实战教训(详见 AI memory `feedback_workbuddy_delegation.md`)

**改之前 grep 全项目找以下 hook 的所有 override 并列出来:**
- `getDataList`
- `customHandleResponse`
- `onLoadMore`
- `onRefresh`
- `onReload`
- `queryData`

报告里要列出 grep 结果。如果你打算改其中任何一个,先停下,请示。**推荐路径就是一个都不改**(详见下面架构)。

### 架构: 并列 controller + view 层混排

```
现状:
  _SearchVideoPanelState (view)
    └─ SearchVideoController (controller, 不动)
        └─ Rx<LoadingState<List<SearchVideoItemModel>>>

M2 后:
  _SearchVideoPanelState (view)
    ├─ SearchVideoController (controller, 一行不动)
    │   └─ List<SearchVideoItemModel>            ← B 站
    └─ YtSearchSupplementController (新)         ← YouTube
        └─ Rx<LoadingState<List<YtVideoItem>>>
  view 层在 buildList 里读两个 controller,
  合并成 List<MixedSearchItem>,SliverGrid 单元格内按类型分发。
```

## 边界

### ✅ 可改 / 新增

- `lib/pages/search_panel/video/view.dart` — 改 `buildList` 内部 + `initState` 加 Get.put
- 新建: `lib/services/youtube/yt_search_supplement.dart`(controller)
- 新建: `lib/common/source/mixed_search_item.dart`(sealed class)
- 新建: `lib/common/widgets/video_card/yt_video_card_h.dart`(YT 卡片)
- 新建: `lib/common/source/source_badge.dart`(角标)
- 改 `lib/services/youtube/yt_search.dart` — **仅**追加分页方法(`searchVideosNext`),不动现有 `searchVideos` 签名

### ❌ 不可改

- `lib/pages/search_panel/video/controller.dart` —— **一行都不改**
- `lib/pages/search_panel/controller.dart` (父类) —— 不动
- `lib/pages/search_panel/view.dart` (父 view) —— 不动
- 任何 `getDataList`、`customHandleResponse`、`onLoadMore`、`onRefresh`、`onReload`、`queryData` —— 不 override 不调用形态变化
- `lib/http/`、`lib/grpc/`、`lib/tcp/` 任何文件
- 评论相关任何代码

## 详细做什么

### Step 1 — 先 grep 列 override

```bash
grep -rn "@override" lib/pages/search_panel/ | grep -iE "getDataList|customHandleResponse|onLoadMore|onRefresh|onReload|queryData"
```

把结果贴在 session log,确认你的改动不会冲击任何 override。

### Step 2 — `lib/common/source/mixed_search_item.dart`(新建)

```dart
import 'package:PiliPlus/models/search/result.dart' show SearchVideoItemModel;
import 'package:PiliPlus/models_new/youtube/yt_video_item.dart';

sealed class MixedSearchItem {
  const MixedSearchItem();
}

class BiliSearchItem extends MixedSearchItem {
  final SearchVideoItemModel item;
  const BiliSearchItem(this.item);
}

class YtSearchItem extends MixedSearchItem {
  final YtVideoItem item;
  const YtSearchItem(this.item);
}

/// 简单交错合并: 每 [biliBatch] 条 B 站后插入 [ytBatch] 条 YouTube,直到任一源耗尽,
/// 之后追加剩余源全部条目。
List<MixedSearchItem> mergeMixed(
  List<SearchVideoItemModel> bili,
  List<YtVideoItem> yt, {
  int biliBatch = 10,
  int ytBatch = 5,
}) {
  final out = <MixedSearchItem>[];
  var bi = 0, yi = 0;
  while (bi < bili.length || yi < yt.length) {
    final bEnd = (bi + biliBatch).clamp(0, bili.length);
    for (var i = bi; i < bEnd; i++) {
      out.add(BiliSearchItem(bili[i]));
    }
    bi = bEnd;

    final yEnd = (yi + ytBatch).clamp(0, yt.length);
    for (var i = yi; i < yEnd; i++) {
      out.add(YtSearchItem(yt[i]));
    }
    yi = yEnd;

    if (bi >= bili.length && yi < yt.length) {
      for (var i = yi; i < yt.length; i++) out.add(YtSearchItem(yt[i]));
      break;
    }
    if (yi >= yt.length && bi < bili.length) {
      for (var i = bi; i < bili.length; i++) out.add(BiliSearchItem(bili[i]));
      break;
    }
  }
  return out;
}
```

### Step 3 — `lib/common/source/source_badge.dart`(新建)

简单 widget,接 `VideoSource`,渲染右上角小标签:
```dart
import 'package:flutter/material.dart';
import 'package:PiliPlus/common/source/video_source.dart';

class SourceBadge extends StatelessWidget {
  final VideoSource source;
  const SourceBadge({super.key, required this.source});

  @override
  Widget build(BuildContext context) {
    final color = switch (source) {
      VideoSource.bilibili => const Color(0xFFFB7299),
      VideoSource.youtube => const Color(0xFFFF0000),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        child: Text(
          source.badge,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
```
**注意**: 用 `withValues(alpha:)` 不要用 deprecated `withOpacity`。

### Step 4 — `lib/services/youtube/yt_search.dart`(改,仅追加)

现有 `searchVideos` 不动。**追加**支持分页:
```dart
class YtSearchService {
  Future<List<YtVideoItem>> searchVideos(String keyword) async { ... }  // 不动

  Future<({List<YtVideoItem> items, dynamic nextPageToken})> searchVideosWithPage(
    String keyword, {
    dynamic continuation,
  }) async {
    final yt = YoutubeExplode();
    try {
      // 首次: yt.search.search(keyword) 返回 SearchList,有 .nextPage()
      // 续: 你需要查 youtube_explode_dart 3.1.0 的真实分页 API
      //     先做 grep 看 search/SearchList 类定义,再决定签名
      // 必须实际跑通,不要凭猜
      ...
    } finally {
      yt.close();
    }
  }
}
```
**实做要点**: youtube_explode_dart 3.1.0 的 `SearchList` 对象本身提供 `.nextPage()` 返回 `SearchList?`。你 controller 层应该**持有 SearchList 对象**(不持有 token),每次调 nextPage。这意味着 yt_search.dart 可能要返回 `SearchList` 对象本身,而非简单 List。

**最稳的实做** (推荐):  controller 直接持有 `YoutubeExplode` 实例 + `SearchList?` 当前页,首屏 search,翻页 currentPage.nextPage()。`yt_search.dart` 这一层就不写分页,把核心逻辑放 controller。决策权在你,只要可行且不破坏现有 `searchVideos` 签名都行。

### Step 5 — `lib/services/youtube/yt_search_supplement.dart`(新建)

```dart
import 'package:get/get.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models_new/youtube/yt_video_item.dart';
import 'package:PiliPlus/services/youtube/yt_mapper.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class YtSearchSupplementController extends GetxController {
  YtSearchSupplementController({required this.keyword});

  final String keyword;
  final Rx<LoadingState<List<YtVideoItem>>> state =
      Rx<LoadingState<List<YtVideoItem>>>(LoadingState<List<YtVideoItem>>.loading());

  final _yt = YoutubeExplode();
  SearchList? _currentPage;
  final List<YtVideoItem> _accumulated = [];
  bool _loadingMore = false;
  bool _exhausted = false;

  @override
  void onInit() {
    super.onInit();
    _firstLoad();
  }

  Future<void> _firstLoad() async {
    try {
      _currentPage = await _yt.search.search(keyword);
      _accumulated.addAll(_currentPage!.map(mapSearchVideo));
      state.value = Success(List.unmodifiable(_accumulated));
    } catch (e, st) {
      // 失败降级: 给空列表,不影响 B 站结果
      state.value = Success(const []);
      // 也可以在这里 log,具体 logger 看项目惯例
    }
  }

  Future<void> onLoadMore() async {
    if (_loadingMore || _exhausted || _currentPage == null) return;
    _loadingMore = true;
    try {
      final next = await _currentPage!.nextPage();
      if (next == null || next.isEmpty) {
        _exhausted = true;
        return;
      }
      _currentPage = next;
      _accumulated.addAll(next.map(mapSearchVideo));
      state.value = Success(List.unmodifiable(_accumulated));
    } catch (_) {
      _exhausted = true;
    } finally {
      _loadingMore = false;
    }
  }

  @override
  void onClose() {
    _yt.close();
    super.onClose();
  }
}
```

**注意点**:
- `Get.put` 时用 tag 区分(见 view 改动)
- 失败降级返回 `Success(const [])`,**不要**让 B 站结果被 YT 的错误拖累
- 严禁 import `commentsClient` 或评论相关

### Step 6 — `lib/common/widgets/video_card/yt_video_card_h.dart`(新建)

参考 `lib/common/widgets/video_card/video_card_h.dart` 的视觉风格,简化版,**接口形态**:
```dart
class YtVideoCardH extends StatelessWidget {
  const YtVideoCardH({super.key, required this.videoItem, this.onTap});
  final YtVideoItem videoItem;
  final VoidCallback? onTap;
  ...
}
```

布局: 横向卡片,左边封面,右上角 `SourceBadge(source: VideoSource.youtube)`,右边标题/作者/时长/播放量。视觉细节可以参考 VideoCardH 但**不要为了完美像素一致而花时间**,M2 阶段视觉过得去就行。

`onTap` 在 M2 阶段:
```dart
onTap: () {
  // M3 才接详情页。M2 先 print + Toast 提示。
  debugPrint('YT card tapped: ${videoItem.videoId}');
  SmartDialog.showToast('YouTube 详情页 M3 阶段接入');
}
```

### Step 7 — `lib/pages/search_panel/video/view.dart`(改)

#### 7a. `initState` 加 YT controller 注入

```dart
@override
void initState() {
  super.initState();
  controller = Get.put(...); // 原有,不动

  if (BuildConfig.kEnableYoutube) {
    Get.put(
      YtSearchSupplementController(keyword: widget.keyword),
      tag: 'yt_${widget.searchType.name}_${widget.tag}',
    );
  }
}
```

#### 7b. `dispose` 加清理

```dart
@override
void dispose() {
  if (BuildConfig.kEnableYoutube) {
    Get.delete<YtSearchSupplementController>(
      tag: 'yt_${widget.searchType.name}_${widget.tag}',
    );
  }
  super.dispose();
}
```

#### 7c. 改 `buildList` 内部

把原 SliverGrid.builder 包进 Obx,合并两源:
```dart
@override
Widget buildList(ThemeData theme, List<SearchVideoItemModel> list) {
  if (!BuildConfig.kEnableYoutube) {
    // 旧路径,完全不变
    return SliverGrid.builder(
      gridDelegate: gridDelegate,
      itemBuilder: (context, index) {
        if (index == list.length - 1) controller.onLoadMore();
        return VideoCardH(
          videoItem: list[index],
          onRemove: () => controller.loadingState
            ..value.data!.removeAt(index)
            ..refresh(),
        );
      },
      itemCount: list.length,
    );
  }

  final ytController = Get.find<YtSearchSupplementController>(
    tag: 'yt_${widget.searchType.name}_${widget.tag}',
  );

  return Obx(() {
    final ytState = ytController.state.value;
    final ytList = ytState is Success<List<YtVideoItem>> ? ytState.response : <YtVideoItem>[];
    final mixed = mergeMixed(list, ytList);
    return SliverGrid.builder(
      gridDelegate: gridDelegate,
      itemBuilder: (context, index) {
        if (index == mixed.length - 1) {
          controller.onLoadMore();
          ytController.onLoadMore();
        }
        final entry = mixed[index];
        return switch (entry) {
          BiliSearchItem(:final item) => Stack(
            children: [
              VideoCardH(
                videoItem: item,
                onRemove: () => controller.loadingState
                  ..value.data!.removeAt(list.indexOf(item))
                  ..refresh(),
              ),
              const Positioned(top: 4, right: 4, child: SourceBadge(source: VideoSource.bilibili)),
            ],
          ),
          YtSearchItem(:final item) => YtVideoCardH(videoItem: item),
        };
      },
      itemCount: mixed.length,
    );
  });
}
```

**注意**:
- B 站卡片要不要加角标?**要**(用户原 v0 草稿就这么写),用 Stack 叠加
- 角标颜色: B 站粉(`#FB7299`),YT 红(`#FF0000`),已在 SourceBadge 内定
- `onRemove` 用 `list.indexOf(item)` 找回原索引(因为 mixed 索引不对)
- import 新加: `BuildConfig`、`SourceBadge`、`VideoSource`、`MixedSearchItem`、`YtVideoCardH`、`YtSearchSupplementController`

### Step 8 — 实跑验收(必做)

```bash
cd /Users/adams/PiliPlus
~/development/flutter/bin/flutter analyze lib/pages/search_panel lib/services/youtube lib/common/source lib/common/widgets/video_card test/youtube
```
要求 0 issue。

```bash
~/development/flutter/bin/flutter test test/youtube/yt_search_test.dart --plain-name "YouTube search"
# (M1 那个 test 应当依然通过,因为本次没动 yt_search.dart 的现有签名)
```

**不需要**跑完整 build 或 iOS 模拟器 — 这是文本层验收,用户晚些会自己装到 iPhone 上测真机交互。

## Session log

写 `docs/sessions/2026-05-15-m2-search-mixed-done.md`,含:
1. 新增 / 修改文件清单
2. **Step 1 的 override grep 结果**(必须贴)
3. `flutter analyze` 输出
4. 关键决策(尤其是分页 API 怎么用、YtSearchService 是否被改造)
5. 给 M3 的注意点 1-2 条

## 输出格式(交还给我)

不超过 300 字的中文摘要:
1. 文件清单
2. override grep 结果(是否冲击 hook)
3. analyze 结果
4. 关键决策
5. 给 M3 的注意点

## 失败时

- 分页 API 不通 → **保留首屏,翻页 disable,在 README 里登记**,继续走 — 不阻塞 M2
- analyze 出 warning → 修到 0,不能修就报告
- override 链发现冲击 → 立刻停,请示,**不要硬改父类**

## 不做什么

- ❌ 不改 `SearchVideoController` 任何字段或方法
- ❌ 不改父类 `SearchPanelController`
- ❌ 不 override `getDataList / customHandleResponse / onLoadMore / onRefresh / onReload`
- ❌ 不接详情页(M3 才做),YT 卡片点击只 Toast
- ❌ 不接评论 (M4 才做)
- ❌ 不优化 SearchFilter(它当前只 filter B 站,不该 filter YT 也不该改)
- ❌ 不动 youtube_explode_dart 版本号
- ❌ 不提交 git
