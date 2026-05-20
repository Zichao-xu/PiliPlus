enum VideoSource {
  bilibili,
  youtube;

  String get badge => switch (this) {
    VideoSource.bilibili => 'B 站',
    VideoSource.youtube => 'YouTube',
  };
}
