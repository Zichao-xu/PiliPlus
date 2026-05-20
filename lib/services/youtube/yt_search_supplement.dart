import 'package:get/get.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models_new/youtube/yt_video_item.dart';
import 'package:PiliPlus/services/youtube/yt_mapper.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class YtSearchSupplementController extends GetxController {
  YtSearchSupplementController({required this.keyword});

  final String keyword;
  final Rx<LoadingState<List<YtVideoItem>>> state =
      Rx<LoadingState<List<YtVideoItem>>>(LoadingState<List<YtVideoItem>>.loading());

  final _yt = YoutubeExplode();
  VideoSearchList? _currentPage;
  final List<YtVideoItem> _accumulated = [];
  bool _loadingMore = false;
  bool _exhausted = false;

  @override
  void onInit() {
    super.onInit();
    _firstLoad();
  }

  Future<void> _firstLoad() async {
    try {
      _currentPage = await _yt.search.search(keyword);
      _accumulated
        ..clear()
        ..addAll(_currentPage!.map(mapSearchVideo));
      state.value = Success(List.unmodifiable(_accumulated));
    } catch (_) {
      // 失败降级: 给空列表,不影响 B 站结果
      state.value = const Success(<YtVideoItem>[]);
    }
  }

  /// 排序联动重拉首屏。YT API 不支持 B 站那种"播放多/新发布"排序参数,
  /// 这里只重拉默认排序首屏,让 UI 上 YT 部分跟着 B 站一起"换一批"。
  Future<void> reload() async {
    _exhausted = false;
    _loadingMore = false;
    _accumulated.clear();
    state.value = LoadingState<List<YtVideoItem>>.loading();
    await _firstLoad();
  }

  Future<void> onLoadMore() async {
    if (_loadingMore || _exhausted || _currentPage == null) return;
    _loadingMore = true;
    try {
      final next = await _currentPage!.nextPage();
      if (next == null || next.isEmpty) {
        _exhausted = true;
        return;
      }
      _currentPage = next;
      _accumulated.addAll(next.map(mapSearchVideo));
      state.value = Success(List.unmodifiable(_accumulated));
    } catch (_) {
      _exhausted = true;
    } finally {
      _loadingMore = false;
    }
  }

  @override
  void onClose() {
    _yt.close();
    super.onClose();
  }
}
