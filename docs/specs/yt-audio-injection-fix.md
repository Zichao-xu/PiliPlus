# YT 高清音频注入 — 根因 + 修法

## 用户反馈

> 「除 360p 其他的是无声音」
> 「播放器的暂停按钮多按几下才到正常逻辑,一开始是 ▶」

## 根因

[yt_video_page.dart](../../lib/pages/yt_video/yt_video_page.dart) 在 split 流(720p+ video-only)情况下:

```dart
await player.open(Media(chosen.url));
await player.setAudioTrack(AudioTrack.uri(chosen.audioUrl!));
```

media_kit 1.1.11 ([commit 14c3ee41](https://github.com/My-Responsitories/media-kit) `media_kit/lib/src/player/native/player/real.dart:782`) 的 `setAudioTrack(AudioTrack.uri(...))` 实际发送的 mpv 命令是:

```
audio-add <url> cache <title> <lang>
```

mpv `audio-add` 的 mode 参数 3 个候选:

- `select`  — 立即加载 + 切换为当前 active 音轨
- `auto`    — 加载,等切换时机
- `cache`   — **只加进 track list,不切换** ← media_kit 用的这个

所以 split 流 video-only 上注入的外部 audio **加进去了但没被选**,active aid 仍是空 → **无声**。
唯独 360p 是 muxed 单流,自带 audio track,所以正常发声。

附带影响:用户反馈「暂停按钮一开始是 ▶,多按几下才正常」—— 高画质 split 流 audio 选择失败后 mpv buffering 卡住,`state.playing` 长时间为 false,controls 镜像就一直显示 ▶。一旦 user 点 toggle,`player.play()` 让 demux 重启,几次之后状态稳。**根治音频注入会同步治这个**。

## 修法

直接调 mpv command,显式用 `select` 模式:

```dart
await player.open(Media(chosen.url));
if (chosen.audioUrl != null) {
  await player.command([
    'audio-add',
    chosen.audioUrl!,
    'select',
    'External',
    'auto',
  ]);
}
```

`Player` 在 `media_kit/player/player.dart` 是 `NativePlayer` 别名,`command(List<String>)` 是公开 API。

## 改动点

[yt_video_page.dart](../../lib/pages/yt_video/yt_video_page.dart):

1. `_startPlayback` 里的初次注入(约 L154-161):`setAudioTrack` → `command(['audio-add', ..., 'select', ...])`
2. `_switchQuality` 里的切换注入(约 L296-301):同上

不动 `AudioTrack` 模型;只是不用 `setAudioTrack(AudioTrack.uri)` 那条路径(因为它写死 `cache`)。

## 验证

- macOS 自测:`flutter analyze` 全过
- 真机:进 YT 视频 → 默认起播应该 HLS 或 1080p split + 有声 → 切到 720p / 480p split → 有声 → 切到 360p muxed → 有声

## 不做

- 不改 media_kit 上游(改了 rebase 成本太高)
- 不动 `AudioTrack` 模型
