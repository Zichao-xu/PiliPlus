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
