# YT 进度条加缓冲条

## 现状

[yt_video_controls.dart:564](../../lib/pages/yt_video/yt_video_controls.dart) 用 Material `Slider`,只有 2 层:active(白色实)+ inactive(white24)。缓冲了多少不知道。

`player.stream.buffer` (media_kit) 给的是 mpv `demuxer-cache-time` 属性,absolute timestamp = buffer end position。

## 目标

进度条 3 层叠加显示:
- 最底:已播放(白色)
- 中间:已缓冲(白 alpha 50%)
- 最上:slider thumb 拖拽

## 实现

### 1. State 订阅 buffer 流

```dart
Duration _buffer = Duration.zero;
// ...
_subs.add(widget.player.stream.buffer.listen((v) {
  if (mounted) setState(() => _buffer = v);
}));
```

### 2. 用 Stack 自定义 progress bar

替换现在的单 `Slider`,改成:
```dart
SizedBox(
  height: 16,
  child: Stack(
    alignment: Alignment.center,
    children: [
      // 1) 底:未缓冲灰
      Container(margin: ..., height: 2.5, color: Colors.white24),
      // 2) 中:已缓冲白 alpha 50%
      FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: hasDur ? (_buffer / total).clamp(0, 1) : 0,
        child: Container(margin: ..., height: 2.5, color: Colors.white.withValues(alpha: 0.5)),
      ),
      // 3) 顶:Slider (active=白,inactive=透明)
      SliderTheme(
        data: SliderTheme.of(context).copyWith(
          activeTrackColor: Colors.white,
          inactiveTrackColor: Colors.transparent,
          ...
        ),
        child: Slider(...同现有...),
      ),
    ],
  ),
)
```

### 3. 缓冲指示器

中央 `_buffering=true` 时已经显示 spinner。不动。

## 不做

- 不引入 audio_video_progress_bar / chewie 等三方依赖
- 不改 PlPlayer(B 站播放器)的进度条 — 那条独立
- 不改 yt_video_page 其他逻辑

## 验收

- 进入 YT 视频起播 → 进度条**应能看到白 alpha 50% 的缓冲段超前于当前白色实条**
- 拖拽 thumb seek 后,缓冲段会先收缩到 thumb 处(demuxer reset),然后随网络拉回来
- 中央 buffering spinner 在 paused-for-cache 时仍正常显示

## 交付

- macOS Debug 自测
- IPA: `~/Desktop/PiliPlus-buffer-bar-2026-05-18.ipa`
