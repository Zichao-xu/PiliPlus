import 'package:PiliPlus/models_new/video/video_detail/stat_detail.dart';
import 'package:PiliPlus/pages/common/common_intro_controller.dart';
import 'package:flutter/material.dart';

class YtIntroController extends CommonIntroController {
  @override
  void queryVideoIntro() {}

  @override
  void actionCoinVideo() {}

  @override
  void actionLikeVideo() {}

  @override
  void actionShareVideo(BuildContext context) {}

  @override
  void actionTriple() {}

  @override
  Future<void> actionFavVideo({bool isQuick = false}) async {}

  @override
  (Object, int) get getFavRidType => throw UnimplementedError();

  @override
  StatDetail? getStat() => null;

  @override
  bool get isShowOnlineTotal => false;

  @override
  void onInit() {
    super.onInit();
    videoDetail.value.title = videoDetailCtr.ytVideoDetail?.title ?? '';
  }

  @override
  bool nextPlay() => false;

  @override
  bool prevPlay() => false;
}
