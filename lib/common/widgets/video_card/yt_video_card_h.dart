import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/stat/stat.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:PiliPlus/models/common/stat_type.dart';
import 'package:PiliPlus/models_new/youtube/yt_video_item.dart';
import 'package:PiliPlus/utils/date_utils.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class YtVideoCardH extends StatelessWidget {
  const YtVideoCardH({super.key, required this.videoItem, this.onTap});

  final YtVideoItem videoItem;
  final VoidCallback? onTap;

  /// 时长格式化为 mm:ss 或 hh:mm:ss
  static String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap:
            onTap ??
            () {
              Get.toNamed(
                '/ytVideo',
                arguments: {'videoId': videoItem.videoId},
              );
            },
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Style.safeSpace,
            vertical: 5,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: Style.aspectRatio,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ClipRRect(
                      borderRadius: Style.mdRadius,
                      child: videoItem.thumbnailUrl == null ||
                              videoItem.thumbnailUrl!.isEmpty
                          ? const ColoredBox(color: Color(0x22808080))
                          : CachedNetworkImage(
                              imageUrl: videoItem.thumbnailUrl!,
                              width: double.infinity,
                              height: double.infinity,
                              fit: BoxFit.cover,
                              fadeInDuration:
                                  const Duration(milliseconds: 120),
                              fadeOutDuration:
                                  const Duration(milliseconds: 120),
                              errorWidget: (_, _, _) =>
                                  const ColoredBox(color: Color(0x22808080)),
                            ),
                    ),
                    // 来源角标(YouTube)由父级搜索 view 在卡片右下统一渲染,
                    // 这里不再叠加,避免重复
                    if (videoItem.duration != null)
                      Positioned(
                        right: 6,
                        bottom: 6,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          child: Text(
                            _formatDuration(videoItem.duration!),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        videoItem.title,
                        textAlign: TextAlign.start,
                        style: TextStyle(
                          fontSize: theme.textTheme.bodyMedium!.fontSize,
                          height: 1.42,
                          letterSpacing: 0.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Row(
                      children: [
                        if (videoItem.uploadDate != null)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Text(
                              DateFormatUtils.dateFormat(
                                videoItem.uploadDate!.millisecondsSinceEpoch ~/
                                    1000,
                              ),
                              style: TextStyle(
                                fontSize: 12,
                                height: 1,
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          ),
                        Flexible(
                          child: Text(
                            videoItem.author,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1,
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    if (videoItem.viewCount != null)
                      StatWidget(
                        type: StatType.view,
                        value: videoItem.viewCount,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
