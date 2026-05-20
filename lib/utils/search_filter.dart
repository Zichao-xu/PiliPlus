import 'package:PiliPlus/models/search/result.dart';
import 'package:PiliPlus/utils/storage_pref.dart';

abstract final class SearchFilter {
  static bool get enabled => Pref.searchFilterEnabled;
  static int get minDuration => Pref.searchMinDuration;
  static int get maxPlayCount => Pref.searchMaxPlayCount;
  static Set<String> get blockedPartitions =>
      Pref.searchBlockedPartitions.toSet();

  static bool shouldFilter(SearchVideoItemModel v) {
    if (!enabled) return false;
    if (v.duration > 0 && v.duration < minDuration) return true;
    if ((v.stat.view ?? 0) >= maxPlayCount) return true;
    if (v.typeName != null && blockedPartitions.contains(v.typeName)) return true;
    return false;
  }
}
