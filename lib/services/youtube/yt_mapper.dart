import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:PiliPlus/models_new/youtube/yt_video_item.dart';

YtVideoItem mapSearchVideo(Video v) {
  return YtVideoItem(
    videoId: v.id.value,
    title: v.title,
    author: v.author,
    duration: v.duration,
    thumbnailUrl: v.thumbnails.highResUrl,
    viewCount: v.engagement.viewCount,
    uploadDate: v.uploadDate,
  );
}
