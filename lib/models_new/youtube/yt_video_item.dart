class YtVideoItem {
  final String videoId;       // video.id.value
  final String title;
  final String author;
  final Duration? duration;   // 直播流可能为 null
  final String? thumbnailUrl; // 取最高分辨率那张
  final int? viewCount;       // 库里可能为 null,允许空
  final DateTime? uploadDate;

  const YtVideoItem({
    required this.videoId,
    required this.title,
    required this.author,
    this.duration,
    this.thumbnailUrl,
    this.viewCount,
    this.uploadDate,
  });
}
