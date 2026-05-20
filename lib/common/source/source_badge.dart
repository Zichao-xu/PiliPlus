import 'package:PiliPlus/common/source/video_source.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// 来源图标角标:搜索混排卡片右下角用。
/// B 站: 用户提供的 PNG 图标(`source_bilibili.png`),
///       图本身有透底留白,显示时放大 1.4x 让有效内容跟 YouTube 视觉等大
/// YouTube: font_awesome YouTube 红色矩形
class SourceBadge extends StatelessWidget {
  final VideoSource source;
  // 视觉等效尺寸 — YT 矩形和 B 站有效内容的目标显示大小
  final double size;
  const SourceBadge({super.key, required this.source, this.size = 16});

  @override
  Widget build(BuildContext context) {
    return switch (source) {
      // B 站 PNG 周边有透底空白,实际 logo 内容约占 70% 图像。
      // 为使有效内容跟 YT 一样大,容器尺寸放大到 size / 0.7。
      VideoSource.bilibili => Image.asset(
          'assets/images/source_bilibili.png',
          width: size / 0.7,
          height: size / 0.7,
          fit: BoxFit.contain,
        ),
      VideoSource.youtube => FaIcon(
          FontAwesomeIcons.youtube,
          size: size,
          color: const Color(0xFFFF0000),
        ),
    };
  }
}
