# Spec: M2 修补 — analyze 错误清单

> 状态: **派活中**
> 上级 spec: `docs/specs/m2-search-mixed.md`
> 失败原因: workbuddy 上一轮 Max turns 出局未自验,代码不编译
> 执行: workbuddy (`kimi-k2.6 + xhigh`)

## 目标

修复 `flutter analyze lib/pages/search_panel lib/services/youtube lib/common/source lib/common/widgets/video_card test/youtube` 报的 **12 个 issue**(7 error + 2 warning + 3 info),做到 **0 issue**。

**不扩 scope**,只修这 12 处。

## 12 issue 清单 + 精准修法

> 文件路径全部基于 `/Users/adams/PiliPlus`。

### 文件 1: `lib/common/source/mixed_search_item.dart`

| 行号 | 类型 | 报错 | 修法 |
|---|---|---|---|
| 42:44 | info | curly_braces_in_flow_control_structures | for 单行体加 `{ }` |
| 46:46 | info | curly_braces_in_flow_control_structures | 同上 |

具体: 第 42 行原是
```dart
for (var i = yi; i < yt.length; i++) out.add(YtSearchItem(yt[i]));
```
改成
```dart
for (var i = yi; i < yt.length; i++) {
  out.add(YtSearchItem(yt[i]));
}
```
第 46 行同理。

### 文件 2: `lib/pages/search_panel/video/view.dart`

| 行号 | 类型 | 报错 | 根因 |
|---|---|---|---|
| 154:22 | **error** | `Success` 未定义 | 缺 import |
| 154:35 | **error** | `YtVideoItem` 不是类型 | 缺 import |
| 155:25 | **error** | `LoadingState<List<YtVideoItem>>.response` 未定义 | Success 未识别的连锁 |
| 156:17 | warning | dead code | 同上连锁 |
| 156:18 | **error** | `YtVideoItem` 不是类型 | 同上 |

**修法**: 在 view.dart 顶部 import 区,**追加两行**(与既有 import 合并排序):

```dart
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models_new/youtube/yt_video_item.dart';
```

`Success` 和 `LoadingState` 类型都在 `lib/http/loading_state.dart` 定义;`YtVideoItem` 在 `lib/models_new/youtube/yt_video_item.dart` 定义。两行 import 解决全部 5 个 issue。

**不要**动 view.dart 其他任何代码,逻辑无问题。

### 文件 3: `lib/services/youtube/yt_search_supplement.dart`

| 行号 | 类型 | 报错 | 修法 |
|---|---|---|---|
| 28:22 | **error** | `VideoSearchList` 不能赋给 `SearchList?` | 改变量类型 |
| 29:45 | **error** | `mapSearchVideo Function(Video)` 不能用于 `Function(SearchResult)` | 28 修后连锁解决 |
| 31:17 | warning | 未使用的 `st` | 删除 stack 变量 |
| 33:21 | info | prefer const constructor | const Success |
| 47:36 | **error** | 同 29 | 28 修后连锁解决 |

**根因**: youtube_explode_dart 3.1.0 的 `yt.search.search(...)` 返回 `Future<VideoSearchList>`, 而 `VideoSearchList extends BasePagedList<Video>`。workbuddy 上轮把变量类型写成 `SearchList?`(`BasePagedList<SearchResult>` 的另一个子类),导致 dart 推断 map 函数应接 `SearchResult` 而不是 `Video`,连锁两个 error。

**修法**:

```dart
// 第 15 行 (原):
SearchList? _currentPage;
// 改为:
VideoSearchList? _currentPage;
```

第 31 行原是:
```dart
} catch (e, st) {
  // 失败降级: 给空列表,不影响 B 站结果
  state.value = Success(const []);
}
```
改为:
```dart
} catch (_) {
  // 失败降级: 给空列表,不影响 B 站结果
  state.value = const Success(<YtVideoItem>[]);
}
```
- `(_)` 替换 `(e, st)` — 去掉未用的 stack
- `const Success(<YtVideoItem>[])` — 显式泛型 + 全 const,消除 prefer_const_constructors info

第 45 行的 nextPage 错误处理段类似,也用 `catch (_)`(如果原来就只有 `(_)` 就不动)。

**不要**动其他任何字段或方法。

## 自验步骤(必做,不跑不交)

```bash
cd /Users/adams/PiliPlus
~/development/flutter/bin/flutter analyze lib/pages/search_panel lib/services/youtube lib/common/source lib/common/widgets/video_card test/youtube
```

**要求**: `0 issues found.`

如果还有 issue,**不要瞎改**,把剩余 issue 原样贴报告,等下一轮 spec。

## 输出格式(交还给我)

不超过 150 字中文摘要,含:
1. 改动 3 文件的具体行号(`view.dart` 加 2 import / `yt_search_supplement.dart` 变量类型 + catch 改写 / `mixed_search_item.dart` 加大括号)
2. `flutter analyze` 实际输出(必须粘最后一行 `0 issues found.` 之类)

## 不做什么

- ❌ 不动 12 issue 之外的任何代码 / 文件
- ❌ 不重构 / 不优化(看着不顺眼也忍住)
- ❌ 不补充功能 / 不加测试
- ❌ 不补 session log(那是上级任务,这次 fix 不归你)
- ❌ 不动 youtube_explode_dart 版本
- ❌ 不提交 git
