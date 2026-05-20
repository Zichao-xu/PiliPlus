# Spec: M3 修补与收尾

> 状态: **派活中**
> 上级: `docs/specs/m3-yt-video-detail.md`
> 失败原因: workbuddy 第 1 轮 Max turns(80) exceeded,未跑 analyze 未写 session log,留下 3 个 analyze issue
> 执行: workbuddy (`kimi-k2.6 + high`)

## 目标

1. 修 3 个 analyze issue → 0 issue
2. 补写 M3 session log

## 3 issue 修法

### issue 1 (error)
`lib/pages/video/introduction/yt/view.dart:90` — `Undefined name 'StatType'`

**修法**: 在该文件顶部 import 区追加:
```dart
import 'package:PiliPlus/models/common/stat_type.dart';
```
**注意**: 如果你看 yt/view.dart 第 90 行用 StatType 的方式不对(比如根本没用 StatWidget),需要回看 m3 spec § Step 3 重写简介区里的播放量展示。**先 Read 该文件全文判断**。

### issue 2 (warning)
`lib/pages/video/controller.dart:45` — `Unused import: yt/controller.dart`

**修法**: 看第 45 行是不是真没显式使用 YtIntroController 类型。如果项目实际通过 `Get.put<YtIntroController>` 或 view 层 `Get.find<YtIntroController>` 引用,这个 import **应放到 view.dart 那里**而非 controller.dart。

把这个 import 从 `lib/pages/video/controller.dart` **移除**,在 `lib/pages/video/view.dart` 顶部加上(view 层 dispatch 时要 instantiate YtIntroController)。

如果 view.dart 实际不需要这个类型(用 string tag 间接寻路),则两处都不用 import,直接删 controller.dart 那行。

### issue 3 (warning)
`lib/pages/video/introduction/yt/controller.dart:4` — `Unused import: get/get.dart`

**修法**: 如果该文件类没 extends 任何 GetX 基类、没用 Rx 等 GetX 符号,直接删该 import。

但 spec § Step 3 要求 `YtIntroController extends CommonIntroController`,CommonIntroController 链上必有 GetX 关系。**先 Read** `lib/pages/common/common_intro_controller.dart`,看它是不是 GetxController 子类。是的话 `get/get.dart` import 通常多余(因为父类 import 链已经间接引入);删之即可。

## Session log 写法

补 `docs/sessions/2026-05-15-m3-yt-detail-done.md`,严格按上级 spec § Step 9 七项必含:

1. **改动 / 新增文件清单**: 用 `git status` 真实输出对照
2. **`isFileSource` 全部引用点分类表**: 你 Step 4.4 应该已经 grep 过,如果没有,**现在再 grep 一次**补上
3. **setDataSource 调用形态**: 贴一段 B 站现有调用代码 + 你 initYtSource 里写的 YT 调用代码
4. **`flutter analyze` 输出最后一行**(改完 3 issue 后跑)
5. **关键决策**:
   - cid=0 占位是否在 controller.dart onInit 引发问题,你怎么处理的
   - DataSource 字段取舍(audioSource / headers / videoQualities 哪些传哪些没传)
   - cover/title 字段怎么从路由 arguments 流过来
6. **已知风险清单**: 至少含 iOS media_kit 是否真能播 YT URL(未真机验证); cid=0 副作用(若有 grep 出未处理点);media_kit 是否需要 User-Agent / Range header(未验证)
7. **给 M4 评论的注意点 1-2 条**: 比如 commentsClient 已知崩 bug(见 M0 session log)

字数控制在 800 字内。

## 自验

```bash
cd /Users/adams/PiliPlus
~/development/flutter/bin/flutter analyze lib/pages/video lib/services/youtube lib/models_new/youtube lib/common/widgets/video_card lib/models/common/video
```
**要求**: `No issues found.`(或仅剩与本次改动无关的既有 warning)

## 输出格式

不超过 200 字中文摘要,含:
1. 3 issue 修法
2. session log 完成 ✓/✗
3. analyze 最后一行

## 不做什么

- ❌ 不动除 3 issue 涉及的文件之外的任何代码
- ❌ 不重做 M3 任何工作(只 fix 和补 session log)
- ❌ 不动 PiliPlus 主工程的 reply 模块、http/grpc/tcp
- ❌ 不提交 git
