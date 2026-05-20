class YtVideoDetail {
  final String videoId;
  final String title;
  final String author;
  final Duration? duration;
  final int? viewCount;
  final int? likeCount;
  final String description;
  final String? thumbnailUrl;
  final DateTime? uploadDate;
  final List<String> keywords;

  const YtVideoDetail({
    required this.videoId,
    required this.title,
    required this.author,
    this.duration,
    this.viewCount,
    this.likeCount,
    this.description = '',
    this.thumbnailUrl,
    this.uploadDate,
    this.keywords = const [],
  });
}
