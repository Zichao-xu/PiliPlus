# Spec: M3 — YouTube 视频详情(播放 + 简介)

> 状态: **派活中(一把梭)**
> 上级 spec: `docs/specs/multi-source-mvp.md` § M3
> 前置: M2 已通过真机验收
> 执行: workbuddy (`kimi-k2.6 + xhigh`)

## 目标

点击搜索结果里的 YouTube 卡片 → 进入视频详情页 → **能播 + 能看简介**。评论 tab 不渲染(M4 才做)。

## 核心范式: 沿用 `isFileSource` 模式

VideoDetailController 已经有 `isFileSource` 这一套**"非 B 站源"的禁交互分发模式**(给本地文件播放用),覆盖 17+ 处判断点。**M3 不发明新模式**,平行扩出一个 `isYtSource`:
- 凡 `isFileSource` 用作"禁交互/禁数据流"判断处,改为 `(isFileSource || isYtSource)`
- 凡 `isFileSource` 用作"走 file 专属分支"处,**不动**(YT 走自己分支)
- 数据初始化处 `if (isFileSource) initFileSource(...)` 后追加 `else if (isYtSource) initYtSource(...)`

`LocalIntroController` 已经是"所有交互 override 为空"的占位 controller — **YtIntroController 完全模仿它**,平行新建。

## 决策(已定,无需追问)

- **路由**: 复用 `/videoV`,通过 `arguments['sourceType'] = SourceType.youtube` + `arguments['ytVideoId'] = 'xxx'` 分发
- **取流**: 只取 muxed 流,封顶 360p(YT 默认 muxed 上限)
- **评论 tab**: M3 不渲染。`showReply` getter 加 `|| isYtSource` 关闭评论 tab
- **简介视觉**: 模仿 `LocalIntroPanel` 但**自渲染 YT 字段**(标题/作者/时长/播放量/描述全文)。无投币/点赞/收藏按钮
- **失败降级**: 取流失败 → 详情页显示 toast "视频不可播放",回退退出

## 边界

### ✅ 可改 / 新增

**新建** (≈6 文件):
- `lib/services/youtube/yt_video.dart` — service: `fetchVideoDetail(videoId)` → 元数据;`fetchMuxedUrl(videoId)` → muxed stream URL
- `lib/models_new/youtube/yt_video_detail.dart` — model(title/author/durationSec/viewCount/description/thumbnailUrl/uploadDate)
- `lib/pages/video/introduction/yt/controller.dart` — `YtIntroController extends CommonIntroController`, 全交互 override 空(模仿 local)
- `lib/pages/video/introduction/yt/view.dart` — `YtIntroPanel`(模仿 LocalIntroPanel layout, 自渲染 YT 字段)
- (可选) `lib/services/youtube/yt_video_init.dart` — 把 `initYtSource` 的实际网络/数据通路集中到此,降 controller.dart 改动复杂度

**改动**:
- `lib/models/common/video/source_type.dart` — enum 加 `youtube`(参照 `file` 的写法)
- `lib/pages/video/controller.dart` — 加 `isYtSource` 字段 + `initYtSource()` 方法 + 17+ 处 `isFileSource` 判断扩展(详见下面 "Step 4 改动地图")
- `lib/pages/video/view.dart` — 同样扩展 `isFileSource` 判断 + 分发 IntroController(local/pgc/ugc/yt)
- `lib/common/widgets/video_card/yt_video_card_h.dart` — `onTap` 从 Toast 改为路由跳转

### ❌ 不可改

- `lib/http/` / `lib/grpc/` / `lib/tcp/` 任何文件
- B 站相关 IntroController(`ugc/`、`pgc/`、`local/`)— 一行不动
- `PlPlayerController` (`lib/plugin/pl_player/controller.dart`)— 不动(只通过 `setDataSource(DataSource(videoSource: url))` 接口传 URL 进去,不改其内部)
- `lib/pages/video/reply/`、`lib/pages/video/reply_new/`(评论模块,M4 才接)
- youtube_explode_dart 版本

## 详细做什么

### Step 1 — 数据通路(`yt_video.dart` + model)

#### `lib/models_new/youtube/yt_video_detail.dart`

```dart
class YtVideoDetail {
  final String videoId;
  final String title;
  final String author;
  final Duration? duration;
  final int? viewCount;
  final String description;
  final String? thumbnailUrl;
  final DateTime? uploadDate;
  const YtVideoDetail({
    required this.videoId,
    required this.title,
    required this.author,
    this.duration,
    this.viewCount,
    this.description = '',
    this.thumbnailUrl,
    this.uploadDate,
  });
}
```

#### `lib/services/youtube/yt_video.dart`

```dart
class YtVideoService {
  /// 拿视频元信息
  Future<YtVideoDetail> fetchDetail(String videoId) async {
    final yt = YoutubeExplode();
    try {
      final v = await yt.videos.get(VideoId(videoId));
      return YtVideoDetail(
        videoId: v.id.value,
        title: v.title,
        author: v.author,
        duration: v.duration,
        viewCount: v.engagement.viewCount,
        description: v.description,
        thumbnailUrl: v.thumbnails.highResUrl,
        uploadDate: v.uploadDate,
      );
    } finally {
      yt.close();
    }
  }

  /// 拿 muxed 流 URL。返回 null 时表示无可用 muxed 流(很少见但要处理)。
  /// 选最高 bitrate 的 muxed 流。
  Future<String?> fetchMuxedUrl(String videoId) async {
    final yt = YoutubeExplode();
    try {
      final manifest = await yt.videos.streamsClient.getManifest(videoId);
      if (manifest.muxed.isEmpty) return null;
      manifest.muxed.toList().sort((a, b) => b.bitrate.compareTo(a.bitrate));
      return manifest.muxed.first.url.toString();
    } finally {
      yt.close();
    }
  }
}
```

**注意**: youtube_explode_dart 3.1.0 实际签名可能略有差异(`bitrate.compareTo`, `url` 类型等),先 Read pub-cache 源码 `~/.pub-cache/hosted/pub.dev/youtube_explode_dart-3.1.0/lib/src/videos/streams/` 确认再写。**M0/M2 经验**: 别凭名字猜。

### Step 2 — SourceType enum

`lib/models/common/video/source_type.dart` 加成员(参照 `file` 的写法,字段空着即可):

```dart
file,
youtube,  // YT 远程视频,与 file 平级的"非 B 站源"
;
```

### Step 3 — IntroController (yt 平行版)

#### `lib/pages/video/introduction/yt/controller.dart`

**完全模仿** `lib/pages/video/introduction/local/controller.dart`:
```dart
class YtIntroController extends CommonIntroController {
  @override void queryVideoIntro() {}
  @override void actionCoinVideo() {}
  @override void actionLikeVideo() {}
  @override void actionShareVideo(context) {}
  @override void actionTriple() {}
  @override Future<void> actionFavVideo({bool isQuick = false}) async {}
  // ... 把 local controller 里所有的 override 都模仿一遍,一律空实现
}
```

**先 Read** `lib/pages/video/introduction/local/controller.dart` 全文,逐个模仿其 override 列表,**确保 abstract method 全部 implement**(避免编译失败)。

#### `lib/pages/video/introduction/yt/view.dart`

模仿 `lib/pages/video/introduction/local/view.dart` 的 layout 风格,**自渲染 YT 字段**:
- 标题(从 `VideoDetailController` 暴露的 `ytVideoDetail` 字段读)
- 作者 / 上传时间
- 时长
- 播放量(用 `StatWidget(type: StatType.view)`)
- 描述全文(可滚动,长按可复制)
- 不显示 投币/点赞/收藏/三连/分享 任何按钮

如果某些 layout 元素跟 LocalIntroPanel 共通,可以直接模仿;不共通就独立写。**视觉过得去即可**,不追求像素级一致。

### Step 4 — VideoDetailController 改动地图

#### 4.1 新增字段
```dart
late bool isYtSource;
String? ytVideoId;            // arguments['ytVideoId']
YtVideoDetail? ytVideoDetail; // 取完元数据后填充,view 层用它渲染简介
String? ytMuxedUrl;            // 取流后填充
```

#### 4.2 onInit 内的分发

找到 `sourceType = args['sourceType'] ?? SourceType.normal;` 那段(~L404),改成:
```dart
sourceType = args['sourceType'] ?? SourceType.normal;
isFileSource = sourceType == SourceType.file;
isYtSource = sourceType == SourceType.youtube;
isPlayAll = sourceType != SourceType.normal && !isFileSource && !isYtSource;
if (isFileSource) {
  initFileSource(args['entry']);
} else if (isYtSource) {
  ytVideoId = args['ytVideoId'];
  initYtSource();
} else if (isPlayAll) {
  ...
}
```

#### 4.3 `initYtSource()` 方法

加在 controller 类内任意位置:
```dart
Future<void> initYtSource() async {
  try {
    final service = YtVideoService();
    final detail = await service.fetchDetail(ytVideoId!);
    ytVideoDetail = detail;
    // 触发 UI 重绘 - 看 controller 现有怎么通知简介区(Rx? GetBuilder?)
    final url = await service.fetchMuxedUrl(ytVideoId!);
    if (url == null) {
      SmartDialog.showToast('视频不可播放');
      return;
    }
    ytMuxedUrl = url;
    // 后续: 调 plPlayerController.setDataSource(DataSource(videoSource: url, ...))
    // 看现有 B 站取流后是怎么塞给 player 的(grep setDataSource),复用同样的入口。
  } catch (e) {
    SmartDialog.showToast('YouTube 视频加载失败: $e');
  }
}
```

**关键不确定性**: setDataSource 的 DataSource 参数有多个字段(headers / audioSource / videoQualities 等),YT muxed 流是单一 URL,大部分字段可能不需要。**Step 4 实做时**: 先 Read `lib/plugin/pl_player/controller.dart` 第 617-820 行,看 setDataSource 签名和 DataSource 类的字段定义,选最小必要参数集传入。

#### 4.4 所有 `isFileSource` 引用点扩展

**规则**:
- **禁交互判断处**(showReply / showRelatedVideo / 投币按钮可见性 / 弹幕区可见性 等): 改为 `(isFileSource || isYtSource)`
- **走 file 专属分支处**(`if (isFileSource) { initFileSource ... }`、reset 时清 file 资源 等): **不动**,YT 走自己的对应分支(若有需要 reset 的资源)
- **数据/逻辑分支处**(setDataSource 内 if/else): 增加 `else if (isYtSource)` 分支

**workbuddy 执行**: 必须先 `grep -nB1 "isFileSource" lib/pages/video/controller.dart lib/pages/video/view.dart`,把全部引用点列出来,**对每一个标注属于上述 3 类的哪一类**,在 session log 里写一张分类表,再开始改。

**预期约 25 处**(controller.dart ~12 处 + view.dart ~13 处),不一定全要改;判断属于"禁交互"类才改。

### Step 5 — Player 接 muxed URL

PlPlayerController 通过 `setDataSource(DataSource(videoSource: url, ...))` 接 URL。在 `initYtSource` 里取完 url 后,在合适的位置调 setDataSource。

**实做要点**:
- B 站取流后塞给 player 的代码在 controller.dart ~L756 附近(`await plPlayerController.setDataSource(...)`),Read 该段,看完整的调用形态(DataSource 是怎么构造的)
- YT 版本: `DataSource(videoSource: ytMuxedUrl, audioSource: ..., headers: ...)` 中 audioSource 不需要(muxed),headers 也不需要(YT CDN 直链)
- 不复用 B 站的 setDataSource 调用点,而是在 `initYtSource` 末尾**单独调一次** setDataSource

**风险**: media_kit 对 YT CDN URL 可能要 Range header / User-Agent 支持。M0 已实测可在 macOS 上拿到 URL 并能 mpv 播,**iOS media_kit 是否兼容**未实测。**如果 setDataSource 后真机无法播**: 把详情记入 session log,作为已知风险 — 不阻塞 M3 收工,补丁留到 M3 fix 阶段。

### Step 6 — 搜索卡片 onTap

`lib/common/widgets/video_card/yt_video_card_h.dart` 内 `onTap` 占位 Toast 改为:
```dart
onTap: onTap ?? () {
  Get.toNamed('/videoV', arguments: {
    'sourceType': SourceType.youtube,
    'ytVideoId': videoItem.videoId,
    'cover': videoItem.thumbnailUrl,
    'title': videoItem.title,
    'cid': 0,  // 占位; B 站路径要 cid,YT 不用,先放 0 看是否触发问题
    'aid': 0,  // 同上
    'heroTag': Utils.makeHeroTag(videoItem.videoId.hashCode),
  });
},
```

**关键不确定性**: VideoDetailController 在 onInit 处可能强依赖 `cid` 非零(`cid = RxInt(args['cid'])`)。**预期需要再调整**: 在 onInit 处对 isYtSource 加保护,跳过 cid 相关逻辑。

### Step 7 — IntroPanel 分发(view.dart)

`lib/pages/video/view.dart` 在分发 IntroController 处(Read 找 LocalIntroPanel 实例化的位置),加 yt 分支:
```dart
if (videoDetailController.isFileSource) {
  // LocalIntroPanel
} else if (videoDetailController.isYtSource) {
  return YtIntroPanel(heroTag: ...);
} else {
  // ugc/pgc IntroPanel
}
```

### Step 8 — 自验

```bash
cd /Users/adams/PiliPlus
~/development/flutter/bin/flutter analyze lib/pages/video lib/services/youtube lib/models_new/youtube lib/common/widgets/video_card lib/models/common/video
~/development/flutter/bin/flutter analyze  # 全工程 sanity
```
**要求**: 0 error。warning 可接受但要列出。

**不需要**: build iOS、跑模拟器、真机测试 — 这些用户做。

### Step 9 — Session log

写 `docs/sessions/2026-05-15-m3-yt-detail-done.md`,必须含:

1. 改动 / 新增文件清单
2. **`isFileSource` 全部引用点的分类表**(Step 4.4 的产出物)
3. setDataSource 调用形态(B 站和 YT 各一段示意代码)
4. `flutter analyze` 输出
5. 关键决策(尤其是 cid=0 占位的处理 / DataSource 字段如何取舍 / cover 字段怎么传)
6. **已知风险清单**(包括: iOS media_kit 是否真能播 YT URL、cid=0 是否引发副作用、retrieve 失败的降级路径是否完整)
7. 给 M4 的注意点

## 必读纪律

1. **不许 Max turns**: 上限 80 turns。**用满之前**必须保存进度: 已改动的文件 git diff 留磁盘 + session log 写半份也比丢了好。如果你 turns 已 ≥ 75 还没完成全部 Step,**立刻交回**当前进度报告,军师会发 fix spec 接力。

2. **不许跳自验**: 任何 issue > 0 不准报"完成"。

3. **不许伪造**: 没真跑 analyze 不准说"通过"。

4. **不许扩 scope**: 没列在边界 ✅ 内的文件,grep 看一眼就走。

5. **不许动评论**: lib/pages/video/reply / reply_new 模块全部回避。

## 输出格式

不超过 500 字中文摘要,含:
1. 文件清单
2. `isFileSource` 分类表行数(只要"N 处分类完毕"汇总)
3. analyze 输出最后一行
4. 关键决策概览
5. 已知风险

## 失败时

- analyze 出 error → 修到 0;改不动就停,把 error 原样贴回,**不要瞎改**
- 真机播放问题(predictable risk)→ 不阻塞 M3 验收,session log 登记
- Max turns 临近 → 主动止损,交进度报告
