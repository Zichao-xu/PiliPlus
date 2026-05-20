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

/// 跨源混排合并 — 1:1 严格轮询交错。
///
/// 设计原则:
/// - B 站和 YouTube 各自的 search API 已按其内部相关度算法排序返回,
///   头部就是最相关结果。我们只需让两源结果**交替穿插**,
///   既保留各源的相关度顺序,又避免单源扎堆。
/// - 不再用 N:M 批次轮换(易扎堆);改 1:1 严格穿插。
/// - 任一源耗尽后,剩余直接追加。
///
/// 跨源"相对相关度"无法计算(两源不提供 score 字段且评分体系不同),
/// 这是大厂搜索聚合时的常见取舍 — 类似 Google、DuckDuckGo 多源聚合
/// 也采用 round-robin 策略。
List<MixedSearchItem> mergeMixed(
  List<SearchVideoItemModel> bili,
  List<YtVideoItem> yt,
) {
  final out = <MixedSearchItem>[];
  var bi = 0, yi = 0;
  while (bi < bili.length || yi < yt.length) {
    if (bi < bili.length) {
      out.add(BiliSearchItem(bili[bi++]));
    }
    if (yi < yt.length) {
      out.add(YtSearchItem(yt[yi++]));
    }
  }
  return out;
}
