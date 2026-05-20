import 'package:PiliPlus/build_config.dart';
import 'package:PiliPlus/common/source/mixed_search_item.dart';
import 'package:PiliPlus/common/source/source_badge.dart';
import 'package:PiliPlus/common/source/video_source.dart';
import 'package:PiliPlus/common/widgets/sliver/sliver_floating_header.dart';
import 'package:PiliPlus/common/widgets/video_card/video_card_h.dart';
import 'package:PiliPlus/common/widgets/video_card/yt_video_card_h.dart';
import 'package:PiliPlus/models/common/search/video_search_type.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/search/result.dart';
import 'package:PiliPlus/models_new/youtube/yt_video_item.dart';
import 'package:PiliPlus/pages/search/widgets/search_text.dart';
import 'package:PiliPlus/pages/search_panel/video/controller.dart';
import 'package:PiliPlus/pages/search_panel/view.dart';
import 'package:PiliPlus/services/youtube/yt_search_supplement.dart';
import 'package:PiliPlus/utils/grid.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class SearchVideoPanel extends CommonSearchPanel {
  const SearchVideoPanel({
    super.key,
    required super.keyword,
    required super.tag,
    required super.searchType,
  });

  @override
  State<SearchVideoPanel> createState() => _SearchVideoPanelState();
}

class _SearchVideoPanelState
    extends
        CommonSearchPanelState<
          SearchVideoPanel,
          SearchVideoData,
          SearchVideoItemModel
        >
    with GridMixin {
  @override
  late final SearchVideoController controller;
  Worker? _sortWorker;
  LoadingState? _prevState;

  @override
  void initState() {
    super.initState();
    controller = Get.put(
      SearchVideoController(
        keyword: widget.keyword,
        searchType: widget.searchType,
        tag: widget.tag,
      ),
      tag: widget.searchType.name + widget.tag,
    );

    if (BuildConfig.kEnableYoutube) {
      Get.put(
        YtSearchSupplementController(keyword: widget.keyword),
        tag: 'yt_${widget.searchType.name}_${widget.tag}',
      );
      // 排序联动: B 站 controller 从 Success → Loading 表示重 query(排序/筛选)
      // 这时让 YT 也 reload 首屏一次,避免"切排序结果不动"
      _sortWorker = ever<LoadingState>(controller.loadingState, (s) {
        if (s is Loading && _prevState is Success) {
          Get.find<YtSearchSupplementController>(
            tag: 'yt_${widget.searchType.name}_${widget.tag}',
          ).reload();
        }
        _prevState = s;
      });
    }
  }

  @override
  void dispose() {
    _sortWorker?.dispose();
    if (BuildConfig.kEnableYoutube) {
      Get.delete<YtSearchSupplementController>(
        tag: 'yt_${widget.searchType.name}_${widget.tag}',
      );
    }
    super.dispose();
  }

  @override
  Widget buildHeader(ThemeData theme) {
    return SliverFloatingHeaderWidget(
      backgroundColor: theme.colorScheme.surface,
      child: Padding(
        padding: const .fromLTRB(12, 0, 12, 4),
        child: Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Wrap(
                  children: [
                    for (final e in ArchiveFilterType.values)
                      Obx(
                        () => SearchText(
                          fontSize: 13,
                          text: e.desc,
                          bgColor: Colors.transparent,
                          textColor: controller.selectedType.value == e
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outline,
                          onTap: (_) => controller
                            ..order = e.name
                            ..selectedType.value = e
                            ..onSortSearch(getBack: false),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const VerticalDivider(indent: 7, endIndent: 8),
            const SizedBox(width: 3),
            SizedBox(
              width: 32,
              height: 32,
              child: IconButton(
                tooltip: '筛选',
                style: const ButtonStyle(
                  padding: WidgetStatePropertyAll(EdgeInsets.zero),
                ),
                onPressed: () => controller.onShowFilterDialog(context),
                icon: Icon(
                  Icons.filter_list_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget buildList(ThemeData theme, List<SearchVideoItemModel> list) {
    if (!BuildConfig.kEnableYoutube) {
      return SliverGrid.builder(
        gridDelegate: gridDelegate,
        itemBuilder: (context, index) {
          if (index == list.length - 1) {
            controller.onLoadMore();
          }
          return VideoCardH(
            videoItem: list[index],
            onRemove: () => controller.loadingState
              ..value.data!.removeAt(index)
              ..refresh(),
          );
        },
        itemCount: list.length,
      );
    }

    final ytController = Get.find<YtSearchSupplementController>(
      tag: 'yt_${widget.searchType.name}_${widget.tag}',
    );

    return Obx(() {
      final ytState = ytController.state.value;
      final ytList =
          ytState is Success<List<YtVideoItem>>
              ? ytState.response
              : <YtVideoItem>[];
      final mixed = mergeMixed(list, ytList);
      return SliverGrid.builder(
        gridDelegate: gridDelegate,
        itemBuilder: (context, index) {
          if (index == mixed.length - 1) {
            controller.onLoadMore();
            ytController.onLoadMore();
          }
          final entry = mixed[index];
          return switch (entry) {
            BiliSearchItem(:final item) => Stack(
              children: [
                VideoCardH(
                  videoItem: item,
                  // 搜索混排:删菜单按钮,统一在卡片右下显示来源 logo
                  showMenu: false,
                  onRemove: () => controller.loadingState
                    ..value.data!.removeAt(list.indexOf(item))
                    ..refresh(),
                ),
                const Positioned(
                  bottom: 6,
                  right: 12,
                  child: SourceBadge(source: VideoSource.bilibili),
                ),
              ],
            ),
            YtSearchItem(:final item) => Stack(
              children: [
                YtVideoCardH(videoItem: item),
                const Positioned(
                  bottom: 6,
                  right: 12,
                  child: SourceBadge(source: VideoSource.youtube),
                ),
              ],
            ),
          };
        },
        itemCount: mixed.length,
      );
    });
  }

  @override
  Widget get buildLoading => gridSkeleton;
}
