import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/stat/stat.dart';
import 'package:PiliPlus/models/common/stat_type.dart';
import 'package:PiliPlus/pages/video/controller.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

class YtIntroPanel extends StatefulWidget {
  const YtIntroPanel({super.key, required this.heroTag});

  final String heroTag;

  @override
  State<YtIntroPanel> createState() => _YtIntroPanelState();
}

class _YtIntroPanelState extends State<YtIntroPanel>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late final _controller =
      Get.find<VideoDetailController>(tag: widget.heroTag);

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    return Obx(() {
      final detail = _controller.ytVideoDetail;
      if (detail == null) {
        return const SliverToBoxAdapter(
          child: Center(child: CircularProgressIndicator()),
        );
      }
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Style.safeSpace),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              Text(
                detail.title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (detail.author.isNotEmpty)
                    Text(
                      detail.author,
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  if (detail.uploadDate != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      '${detail.uploadDate!.year}-${detail.uploadDate!.month.toString().padLeft(2, '0')}-${detail.uploadDate!.day.toString().padLeft(2, '0')}',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (detail.duration != null)
                    _buildChip(
                      theme,
                      DurationUtils.formatDuration(
                        detail.duration!.inSeconds,
                      ),
                    ),
                  if (detail.viewCount != null) ...[
                    const SizedBox(width: 8),
                    StatWidget(
                      type: StatType.view,
                      value: detail.viewCount!,
                      iconSize: 13,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ],
              ),
              if (detail.description.isNotEmpty) ...[
                const SizedBox(height: 12),
                GestureDetector(
                  onLongPress: () {
                    Clipboard.setData(ClipboardData(text: detail.description));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已复制描述')),
                    );
                  },
                  child: Text(
                    detail.description,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildChip(ThemeData theme, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
