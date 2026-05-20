# Spec: M2 修补 — YT 缩略图灰图

> 状态: **派活中**
> 上级: `docs/specs/m2-search-mixed.md`
> 失败现象: 真机翻墙后 YT 卡片标题/作者/时长全对,**缩略图全灰**
> 根因: `lib/common/widgets/image/network_img_layer.dart` 内部用 `ImageUtils.thumbnailUrl(src, quality)` 转换 URL,该函数把无后缀的 URL 强加 `@1q.webp`,YT 的 `https://img.youtube.com/vi/xxx/hqdefault.jpg` 被变成 `...hqdefault.jpg@1q.webp` 导致 YouTube CDN 404。

## 目标

YT 卡片缩略图正常显示,B 站逻辑零影响。

## 边界

- ✅ **只改** `lib/common/widgets/video_card/yt_video_card_h.dart`
- ❌ **不动** `NetworkImgLayer` / `ImageUtils.thumbnailUrl` 任何已有文件
- ❌ 不引入新依赖(`cached_network_image` 已在 pubspec)

## 做什么

在 `yt_video_card_h.dart` 内,把缩略图 `NetworkImgLayer(...)` 那一段替换为 `CachedNetworkImage` 直连。匹配原视觉(`borderRadius` + `fit: cover`)。

具体: 当前(约第 43-47 行)是:
```dart
NetworkImgLayer(
  src: videoItem.thumbnailUrl,
  width: double.infinity,
  height: double.infinity,
),
```

改为:
```dart
ClipRRect(
  borderRadius: BorderRadius.circular(Style.mdRadius.topLeft.x),
  child: videoItem.thumbnailUrl == null || videoItem.thumbnailUrl!.isEmpty
      ? const ColoredBox(color: Color(0x22808080))
      : CachedNetworkImage(
          imageUrl: videoItem.thumbnailUrl!,
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.cover,
          fadeInDuration: const Duration(milliseconds: 120),
          fadeOutDuration: const Duration(milliseconds: 120),
          errorWidget: (_, __, ___) =>
              const ColoredBox(color: Color(0x22808080)),
        ),
),
```

import 调整:
- 加 `import 'package:cached_network_image/cached_network_image.dart';`
- 删 `import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';`(若全文已无用)
- `Style` 已在原 imports

**关于 `Style.mdRadius.topLeft.x`**: 你需要先 Read `lib/common/style.dart` 确认 `mdRadius` 实际是什么类型(可能就是 BorderRadius 而非半径数值)。**实际正确写法**: 如果 `Style.mdRadius` 是 `BorderRadius` 类型,直接用 `borderRadius: Style.mdRadius`;否则按其形态构造。**先 Read 再写**,不要瞎猜。

## 自验

```bash
cd /Users/adams/PiliPlus
~/development/flutter/bin/flutter analyze lib/common/widgets/video_card/yt_video_card_h.dart
```
要求 `No issues found.`

## 输出格式

不超过 100 字中文摘要,含:
1. 改动具体行号
2. 用了 `Style.mdRadius` 的什么形态
3. analyze 输出

## 不做什么

- ❌ 不改 NetworkImgLayer / ImageUtils.thumbnailUrl
- ❌ 不改 yt_video_card_h.dart 其他部分(时长 / 标题 / 角标布局都不动)
- ❌ 不动 B 站 VideoCardH(它本来就吃 NetworkImgLayer 没问题)
- ❌ 不提交 git
