# Spec: M1 — YouTube 数据源骨架进主工程

> 状态: **派活中**
> 上级 spec: `docs/specs/multi-source-mvp.md` § M1
> M0 验收: `docs/sessions/2026-05-15-yt-poc-done.md`
> 执行: workbuddy (`kimi-k2.6 + xhigh`)

## 目标

把 M0 验证过的 youtube_explode_dart 接口形态,搬进 PiliPlus 主工程,**不接入任何 UI**,只立数据通路骨架 + 一份能跑通的 search 测试。

完成判据:
1. `flutter pub get` 干净通过
2. `flutter analyze` 干净通过(不引入新 warning)
3. `flutter test test/youtube/yt_search_test.dart` 真实搜出 YouTube 视频,test 不 mock

## 边界

- ✅ 改 `pubspec.yaml`(加一个依赖)
- ✅ 新建 `lib/common/source/`、`lib/services/youtube/`、`lib/models_new/youtube/`、`test/youtube/` 四个新目录及其文件
- ❌ **不动**任何已有 dart 文件(`lib/pages/`、`lib/http/`、`lib/grpc/`、`lib/main.dart` 等)
- ❌ **不接 UI**(搜索页 / 详情页 / 评论 一律不碰)
- ❌ **不写 commentsClient 相关代码**(M4 阶段单独处理)
- ❌ **不引入"通用 source 抽象接口"**(MVP 不抽象)

## 输入(精确路径)

- 工作目录: `/Users/adams/PiliPlus`
- POC 已验证的 API 形态: `/Users/adams/PiliPlus/docs/sessions/2026-05-15-yt-poc-done.md` § "已确认可用的 API 形态"
- 项目风格参考:
  - GetxService 范例: `lib/services/account_service.dart`(看 `extends GetxService` + `onInit`)
  - service_locator 范例: `lib/services/service_locator.dart`(看怎么挂全局)
  - LoadingState 范例: `lib/http/loading_state.dart`(看 sealed class `Success<T>` / `Loading` / `Error` 形态)
  - model 范例: `lib/models_new/search/search_rcmd/data.dart`(看 fromJson / 字段命名)
- POC 工程(只读参考): `scratch/yt_poc/bin/*.dart`

## 做什么

### 1. `pubspec.yaml`

在 `dependencies:` 段加(位置: 紧贴 `dio:` 那一行下面,跟其他网络库放一起):
```yaml
  youtube_explode_dart: ^3.1.0
```
版本就锁 3.1.0(M0 验证过,**不要自己升版本**)。

### 2. `lib/build_config.dart`

读现有内容,在合适位置追加:
```dart
  static const bool kEnableYoutube = true;  // M1: feature flag,出问题时改 false 一键回退
```
**注意**: build_config.dart 已存在,你只能追加常量,不要改动现有字段。先 `Read` 整个文件,确认追加位置(类内末尾)再 Edit。

### 3. `lib/common/source/video_source.dart`(新建)

```dart
enum VideoSource {
  bilibili,
  youtube;

  String get badge => switch (this) {
    VideoSource.bilibili => 'B 站',
    VideoSource.youtube => 'YouTube',
  };
}
```
- 不引依赖
- 不加 fromString / toJson — 现在用不到

### 4. `lib/models_new/youtube/yt_video_item.dart`(新建)

最小字段集,**对齐 M0 实测可用字段**:
```dart
class YtVideoItem {
  final String videoId;       // video.id.value
  final String title;
  final String author;
  final Duration? duration;   // 直播流可能为 null
  final String? thumbnailUrl; // 取最高分辨率那张
  final int? viewCount;       // 库里可能为 null,允许空

  const YtVideoItem({
    required this.videoId,
    required this.title,
    required this.author,
    this.duration,
    this.thumbnailUrl,
    this.viewCount,
  });
}
```
- 不写 fromJson(数据源不是 JSON,是 youtube_explode_dart 的 `Video` 对象)
- 不写 toJson、equals、hashCode — 现在用不到

### 5. `lib/services/youtube/yt_mapper.dart`(新建)

提供把 `youtube_explode_dart` 的 `Video` / `SearchVideo` 对象转成 `YtVideoItem` 的纯函数:
```dart
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:PiliPlus/models_new/youtube/yt_video_item.dart';

YtVideoItem mapSearchVideo(Video v) {
  return YtVideoItem(
    videoId: v.id.value,
    title: v.title,
    author: v.author,
    duration: v.duration,
    thumbnailUrl: v.thumbnails.highResUrl,
    viewCount: v.engagement.viewCount,
  );
}
```
注意: youtube_explode_dart 的 search 返回 `SearchVideo`,直接看 `_yt.search.search(...).then((it) => it.toList())` 的元素类型,**先 grep 确认元素类型再写**(可能是 `SearchVideo extends Video` 或独立类)。如果字段名不对,以库的实际定义为准并在 PR 注释里说明改动。

### 6. `lib/services/youtube/yt_search.dart`(新建)

```dart
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:PiliPlus/models_new/youtube/yt_video_item.dart';
import 'package:PiliPlus/services/youtube/yt_mapper.dart';

class YtSearchService {
  Future<List<YtVideoItem>> searchVideos(String keyword) async {
    final yt = YoutubeExplode();
    try {
      final results = await yt.search.search(keyword);
      return results.map(mapSearchVideo).toList();
    } finally {
      yt.close();
    }
  }
}
```
- **不**做 GetX 单例注册(M1 阶段;调用者自行 `new YtSearchService()`)
- 不引 LoadingState — service 层只返回原始 future,UI 层包 LoadingState(M2 做)

### 7. `test/youtube/yt_search_test.dart`(新建)

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:PiliPlus/services/youtube/yt_search.dart';

void main() {
  // 真实网络,不 mock。CI 不跑此 test。
  test('YouTube search returns at least 5 results',
      skip: 'requires network; run manually with `flutter test --plain-name "YouTube search"`',
      () async {
    final service = YtSearchService();
    final results = await service.searchVideos('lex fridman');
    expect(results.length, greaterThanOrEqualTo(5));
    expect(results.first.videoId, isNotEmpty);
    expect(results.first.title, isNotEmpty);
  });
}
```
spec 要求 test 文件要写,但默认 `skip` 避免污染 CI;**派活时要真的把 skip 去掉跑一次本地** 确认通过,再恢复 skip 提交。

### 8. 实跑验收(必做,不要跳)

按顺序跑(全在 `/Users/adams/PiliPlus` 根目录):

```bash
~/development/flutter/bin/flutter pub get
~/development/flutter/bin/flutter analyze lib/common/source lib/models_new/youtube lib/services/youtube test/youtube
# 临时去掉 test 里的 skip 跑一次
~/development/flutter/bin/flutter test test/youtube/yt_search_test.dart --plain-name "YouTube search"
# 跑通后把 skip 加回去
```

必须全部通过才算 M1 完成。

### 9. Session log

写 `docs/sessions/2026-05-15-m1-yt-skeleton-done.md`,含:
- 新增文件清单
- pubspec.yaml diff 摘要
- `flutter analyze` 实际输出(0 warning 0 issue 也要写)
- `flutter test` 实际输出(返回了多少条)
- 踩到的坑(预期: 字段名对不上、import 缺失等)
- 给 M2 的注意点

## 必读纪律(写代码前)

### 9.1 不要扩 scope

只动 spec 列出的文件。看到 search_panel/controller.dart 里有"如果加 youtube 就要这里改"的诱惑,**忍住**,那是 M2。

### 9.2 不要碰评论

`commentsClient` / `Comment` / `CommentsList` 一律不 import 不引用,M4 才处理。

### 9.3 命名

- 类名前缀统一 `Yt`(`YtVideoItem`, `YtSearchService`),不用 `YouTube` 前缀(太长)
- 文件名小写下划线: `yt_video_item.dart`、`yt_search.dart`

## 输出格式(交还给我)

不超过 250 字的中文摘要,含:
1. 新增 / 修改文件清单(`A path/to/file` / `M path/to/file`)
2. `flutter analyze` 结果
3. `flutter test` 结果
4. 关键决策点(若有,如字段名替换)
5. 给 M2 的注意点 1-2 条

## 失败时

- `pub get` 失败 → 报错信息原样贴回,**不要乱改版本**
- `analyze` 出 warning → 修到 0,不能修就报告
- `test` 真实网络失败 → 报告,**不要伪造输出**,test 文件加 skip 保留待用户再跑
- 任何一步卡住 → 老实说,不要硬上

## 不做什么

- ❌ 不动 `lib/pages/`、`lib/http/`、`lib/grpc/`、`lib/tcp/` 任何文件
- ❌ 不动 `lib/main.dart` 或 `lib/services/service_locator.dart`
- ❌ 不写 commentsClient 相关代码
- ❌ 不引入 "source 抽象基类"
- ❌ 不在 M1 阶段做 GetX 注册(`Get.put<YtSearchService>` 留到 M2 视需要再决)
- ❌ 不动 youtube_explode_dart 版本号
- ❌ 不删 / 改 `scratch/yt_poc/` 任何文件
- ❌ 不提交 git
