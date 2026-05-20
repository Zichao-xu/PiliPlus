# 2026-05-15 M1 YouTube 数据源骨架进主工程

> 上级 spec: `docs/specs/multi-source-mvp.md` § M1
> 派活 spec: `docs/specs/m1-yt-source-skeleton.md`

## 新增文件

- `lib/common/source/video_source.dart` — VideoSource enum(bilibili / youtube)
- `lib/models_new/youtube/yt_video_item.dart` — YtVideoItem 最小模型
- `lib/services/youtube/yt_mapper.dart` — youtube_explode_dart Video → YtVideoItem 映射
- `lib/services/youtube/yt_search.dart` — YtSearchService 搜索封装
- `test/youtube/yt_search_test.dart` — 真实网络搜索测试

## 修改文件

- `pubspec.yaml` — 新增依赖 `youtube_explode_dart: ^3.1.0`
- `lib/build_config.dart` — 新增 `kEnableYoutube = true` feature flag

## 验收结果

### flutter pub get
干净通过，youtube_explode_dart 3.1.0 成功解析。

### flutter analyze
```
Analyzing 4 items...
No issues found! (ran in 2.3s)
```

### flutter test (真实网络，临时去掉 skip)
```
00:00 +0: loading .../yt_search_test.dart
00:00 +0: YouTube search returns at least 5 results
00:01 +1: All tests passed!
```
搜索 "lex fridman" 返回结果 >= 5 条，videoId 与 title 均非空。

## 踩坑记录

无。字段名 `video.id.value`、`video.title`、`video.author`、`video.duration`、`video.thumbnails.highResUrl`、`video.engagement.viewCount` 均与 M0 POC 一致，一次编译通过。

## 给 M2 的注意点

1. **YtSearchService 生命周期**: M1 没做 GetX 单例注册，M2 接入 UI 时要决定是 `Get.put()` 还是调用处临时 new。临时 new 的缺点是每次搜索都重新 init token，可能有性能损耗。
2. **搜索分页**: `yt.search.search(keyword)` 只返回第一页，M2 需要研究 `nextPage()` 的等价物或翻页参数。
