// M3v2 — YouTube 视频详情页
// 独立 page,不复用 VideoDetailController / PlPlayerController / PlPlayer view widget。
// 直接使用 media_kit 的 Player + media_kit_video 的 Video widget。
// 详见: docs/sessions/2026-05-15-m3-grayed.md

import 'package:PiliPlus/common/widgets/yt_translatable_text.dart';
import 'package:PiliPlus/models_new/youtube/yt_video_detail.dart';
import 'package:PiliPlus/pages/yt_video/yt_comments_view.dart';
import 'package:PiliPlus/pages/yt_video/yt_video_controls.dart';
import 'package:PiliPlus/services/youtube/yt_like_service.dart';
import 'package:PiliPlus/services/youtube/yt_translate_service.dart';
import 'package:PiliPlus/services/youtube/yt_video.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/yt_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class YtVideoPage extends StatefulWidget {
  const YtVideoPage({super.key});

  @override
  State<YtVideoPage> createState() => _YtVideoPageState();
}

class _YtVideoPageState extends State<YtVideoPage>
    with SingleTickerProviderStateMixin {
  Player? _player;
  VideoController? _videoController;
  late final String _videoId;
  late final TabController _tabCtr;

  YtVideoDetail? _detail;
  String? _playerError;
  bool _detailLoading = true;
  bool _streamLoading = false; // 改成手动播放:默认不在加载
  bool _playStarted = false; // 用户主动点 ▶ 才置 true
  bool _isFullscreen = false;
  bool _descExpanded = false;
  bool _tagsExpanded = false;
  List<String>? _translatedKeywords; // batch 翻译后的 tags,null 表示未翻译
  bool _translatingTags = false;
  YtLikeStatus _likeStatus = YtLikeStatus.none;
  List<YtMuxedStreamOption> _streams = const [];
  int _currentQualityIdx = 0;
  List<YtSubtitleTrackInfo> _subtitleTracks = const [];
  int _currentSubtitleIdx = -1; // -1 表示关闭
  String? _currentTranslateLang; // null = 显示 native;非 null = 翻译目标 langCode

  @override
  void initState() {
    super.initState();
    final args = Get.arguments;
    _videoId = args is Map ? args['videoId'] as String : '';
    _tabCtr = TabController(length: 2, vsync: this);
    _bootstrap();
  }

  /// 进页面只 fire 简介,不起播。播放等用户点 ▶。
  Future<void> _bootstrap() async {
    if (_videoId.isEmpty) {
      if (mounted) {
        setState(() {
          _playerError = 'videoId 缺失';
          _detailLoading = false;
        });
      }
      return;
    }
    final svc = YtVideoService();
    try {
      final detail = await svc.fetchDetail(_videoId);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _detailLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _detailLoading = false);
      SmartDialog.showToast('YouTube 简介加载失败: $e');
    }
  }

  /// 用户点 ▶ 触发:取流 + 初始化 player + 打开
  Future<void> _startPlayback() async {
    if (_playStarted) return;
    setState(() {
      _playStarted = true;
      _streamLoading = true;
      _playerError = null;
    });
    final svc = YtVideoService();
    try {
      // 1. 取流(优先 Innertube + poToken,失败 fallback)
      final streamsFut = svc.fetchMuxedStreams(_videoId);

      // 2. 同时初始化 player(并行)
      final player = await Player.create(
        configuration: const PlayerConfiguration(
          // 32MB:split 双流要分别 cache video + audio,4MB 不够
          bufferSize: 32 * 1024 * 1024,
        ),
      );
      final controller = await VideoController.create(player);
      // mpv 起播加速 + 硬解
      player.setProperty('cache', 'yes');
      player.setProperty('cache-pause', 'yes'); // 缓冲不足时主动 pause 等数据,避免卡顿期间继续吃 audio 让 sync 漂
      player.setProperty('cache-pause-initial', 'no');
      player.setProperty('cache-pause-wait', '0.5'); // 至少缓冲 0.5s 才继续播
      player.setProperty('cache-secs', '60'); // 全局 cache 60s,split 流硬要求
      player.setProperty('demuxer-readahead-secs', '30'); // 1→30:split 双流需要充足 demux 余量;1 几乎必 sync 漂移
      player.setProperty('demuxer-max-bytes', '128MiB');
      player.setProperty('demuxer-max-back-bytes', '32MiB');
      player.setProperty('hr-seek', 'yes');
      player.setProperty('hr-seek-framedrop', 'yes');
      player.setProperty('network-timeout', '10');
      player.setProperty('hwdec', 'auto-safe');
      player.setProperty('hwdec-codecs', 'all');
      player.setProperty('audio-fallback-to-null', 'yes');
      // YT split 双流 audio/video sync 校正:容忍 0.2s 内的小偏,超出靠 framedrop 追平
      player.setProperty('audio-pts-correction-threshold', '0.05');
      player.setProperty('framedrop', 'vo'); // 落后只丢 vo 帧,不丢解码帧
      player.setProperty('stream-lavf-o',
          'reconnect=1,reconnect_streamed=1,reconnect_delay_max=2,multiple_requests=1');
      // 登录态把 Cookie 注入 mpv,split 高画质 URL 不再 403
      final ytCookies = YtAuthService.cookies;
      final cookieHeader = (ytCookies != null && ytCookies.isNotEmpty)
          ? ytCookies.entries.map((e) => '${e.key}=${e.value}').join('; ')
          : null;
      player.setMediaHeader(
        userAgent:
            'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
            'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
        headers: cookieHeader != null ? {'Cookie': cookieHeader} : null,
      );
      if (!mounted) {
        await player.dispose();
        return;
      }
      setState(() {
        _player = player;
        _videoController = controller;
      });

      // 3. 等流列表
      final streams = await streamsFut;
      if (!mounted) return;
      if (streams.isEmpty) {
        setState(() {
          _playerError = '该视频无可用 muxed 流';
          _streamLoading = false;
        });
        return;
      }
      _streams = streams;
      _currentQualityIdx = _pickInitialQualityIdx(streams);
      final chosen = streams[_currentQualityIdx];
      await player.open(Media(chosen.url));
      if (chosen.audioUrl != null) {
        await _addExternalAudio(player, chosen.audioUrl!);
      }
      if (mounted) {
        setState(() => _streamLoading = false);
      }
      // 4. 拉字幕(失败不阻塞)
      svc.fetchSubtitleTracks(_videoId).then((tracks) {
        if (!mounted) return;
        setState(() => _subtitleTracks = tracks);
        _applyDefaultSubtitle(tracks);
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _playerError = '$e';
          _streamLoading = false;
        });
      }
    }
  }

  /// 按 [SettingBoxKey.ytSubtitleDefault] 应用默认字幕。
  /// - 'off': 不开字幕
  /// - 'native': 优先 zh,否则首条
  /// - 'translate': 优先 zh,无则首条,然后翻译为 ytSubtitleTranslateLang
  void _applyDefaultSubtitle(List<YtSubtitleTrackInfo> tracks) {
    if (tracks.isEmpty) return;
    final pref = GStorage.setting
        .get(SettingBoxKey.ytSubtitleDefault, defaultValue: 'native') as String;
    if (pref == 'off') return;
    var idx = tracks.indexWhere((t) => t.langCode.startsWith('zh'));
    if (idx < 0) idx = 0;
    if (pref == 'translate') {
      final lang = GStorage.setting.get(
        SettingBoxKey.ytSubtitleTranslateLang,
        defaultValue: 'zh-Hans',
      ) as String;
      // 找语言名(简单 fallback 用 lang code 当 name)
      _setSubtitleTranslated(idx, lang, lang);
    } else {
      _setSubtitle(idx);
    }
  }

  Future<void> _setSubtitle(int idx) async {
    final player = _player;
    if (player == null) return;
    if (idx < 0 || idx >= _subtitleTracks.length) {
      // 关字幕
      await player.setSubtitleTrack(SubtitleTrack.no());
      if (mounted) {
        setState(() {
          _currentSubtitleIdx = -1;
          _currentTranslateLang = null;
        });
      }
      return;
    }
    final t = _subtitleTracks[idx];
    await player.setSubtitleTrack(SubtitleTrack.uri(t.url, title: t.label));
    if (mounted) {
      setState(() {
        _currentSubtitleIdx = idx;
        _currentTranslateLang = null;
      });
    }
  }

  /// 把指定 native track 翻译为目标语言 [tlang]
  Future<void> _setSubtitleTranslated(int nativeIdx, String tlang, String tlangName) async {
    final player = _player;
    if (player == null) return;
    if (nativeIdx < 0 || nativeIdx >= _subtitleTracks.length) return;
    final t = _subtitleTracks[nativeIdx];
    final url = YtVideoService.translateUrl(t.url, tlang);
    await player.setSubtitleTrack(
      SubtitleTrack.uri(url, title: '${t.label} → $tlangName'),
    );
    if (mounted) {
      setState(() {
        _currentSubtitleIdx = nativeIdx;
        _currentTranslateLang = tlang;
      });
    }
  }

  /// 按设置 [SettingBoxKey.ytDefaultQuality] 选起播流。
  /// - 'auto'(默认):优先 '自动 (HLS)' (mpv ABR seamless),无 HLS 则首个非 split
  /// - '1080p' / '720p' / '360p':匹配该 qualityLabel,无则降一级,最后兜首个非 split
  int _pickInitialQualityIdx(List<YtMuxedStreamOption> streams) {
    final pref = GStorage.setting
        .get(SettingBoxKey.ytDefaultQuality, defaultValue: 'auto') as String;
    int firstMuxed() {
      final i = streams.indexWhere((s) => !s.isSplit);
      return i < 0 ? 0 : i;
    }
    if (pref == 'auto') {
      final hls = streams.indexWhere((s) => s.qualityLabel.contains('HLS'));
      return hls >= 0 ? hls : firstMuxed();
    }
    // 精确匹配 e.g. "1080p"
    final exact = streams.indexWhere((s) => s.qualityLabel == pref);
    if (exact >= 0) return exact;
    // 找不到就按数字降序匹配最近的小一档
    final target = int.tryParse(pref.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    if (target > 0) {
      int bestIdx = -1;
      int bestQ = 0;
      for (var i = 0; i < streams.length; i++) {
        final s = streams[i];
        final q = int.tryParse(
                s.qualityLabel.replaceAll(RegExp(r'[^0-9]'), '')) ??
            0;
        if (q > 0 && q <= target && q > bestQ) {
          bestQ = q;
          bestIdx = i;
        }
      }
      if (bestIdx >= 0) return bestIdx;
    }
    return firstMuxed();
  }

  Future<void> _switchQuality(int idx) async {
    if (idx < 0 || idx >= _streams.length || idx == _currentQualityIdx) return;
    final player = _player;
    if (player == null) return;
    final option = _streams[idx];
    final pos = player.state.position;
    setState(() => _currentQualityIdx = idx);
    // muxed 直接 open(先清 audio-files,免得继承之前的);split 在 open 前注入 audio-files
    if (option.audioUrl == null) {
      await player.open(Media(option.url));
      if (pos > Duration.zero) await player.seek(pos);
      return;
    }
    // split: open 视频流 → audio-add select 注入外部 audio → seek
    // 失败 fallback: 等 20s 后还没起 duration → 切回 muxed(360p)
    try {
      await player.open(Media(option.url));
      await _addExternalAudio(player, option.audioUrl!);
      if (pos > Duration.zero) await player.seek(pos);
      // 20 秒后检查 duration 是否就绪;duration==0 视为 demux 失败
      Future<void>.delayed(const Duration(seconds: 20), () async {
        if (!mounted) return;
        if (_currentQualityIdx != idx) return; // 用户中途又切了
        final stuck = player.state.duration.inMilliseconds == 0;
        if (stuck) {
          final muxedIdx = _streams.indexWhere((s) => !s.isSplit);
          if (muxedIdx >= 0 && muxedIdx != _currentQualityIdx) {
            await _switchQuality(muxedIdx);
            if (mounted) {
              SmartDialog.showToast('高画质流加载失败,已回退到 ${_streams[muxedIdx].qualityLabel}');
            }
          }
        }
      });
    } catch (e) {
      // open / setAudioTrack 直接抛异常 → 立即 fallback
      final muxedIdx = _streams.indexWhere((s) => !s.isSplit);
      if (muxedIdx >= 0 && muxedIdx != _currentQualityIdx) {
        await _switchQuality(muxedIdx);
        if (mounted) {
          SmartDialog.showToast('高画质流不可用,已回退');
        }
      }
    }
  }

  /// 给 split 流注入外部 audio。
  ///
  /// 重要:**等主 media 的 duration ready 再发 audio-add**。
  /// mpv 在 loadfile 后 demuxer 没就绪期间发的 audio-add 会被 silent drop / 覆盖,
  /// 这是上一轮 `setAudioTrack(AudioTrack.uri)` 改 `command(['audio-add',...,'select',...])`
  /// 后真机仍无声的根因(改了 mode 但没改时序)。
  ///
  /// 参数精简到 3 个:audio-add 第 4 个 lang 期望 ISO 639 code,
  /// 之前传 'auto' 可能让 mpv parser 拒整条命令(silent)。
  Future<void> _addExternalAudio(Player player, String audioUrl) async {
    // 等 stream.duration 第一次非零(主 media demuxer ready),timeout 4s 兜底
    try {
      await player.stream.duration
          .firstWhere((d) => d.inMilliseconds > 0)
          .timeout(const Duration(seconds: 4));
    } catch (_) {
      // timeout 也继续发,赌一把(主 file 可能本身就是 0 duration 直播流之类)
    }
    if (!mounted) return;
    await player.command(['audio-add', audioUrl, 'select']);
  }

  Future<void> _toggleFullscreen() async {
    final next = !_isFullscreen;
    if (next) {
      await SystemChrome.setPreferredOrientations(
          [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      await SystemChrome.setPreferredOrientations(
          [DeviceOrientation.portraitUp]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    if (mounted) setState(() => _isFullscreen = next);
  }

  @override
  void dispose() {
    _tabCtr.dispose();
    _player?.dispose();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Widget _buildPlayerArea() {
    if (_playerError != null) {
      // 错误状态:显示错误 + 重试按钮
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SelectableText(
                  '播放器错误:\n$_playerError',
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                  textAlign: TextAlign.left,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试播放'),
                  onPressed: () {
                    setState(() {
                      _playStarted = false;
                      _playerError = null;
                    });
                    _startPlayback();
                  },
                ),
              ],
            ),
          ),
        ),
      );
    }
    // 1) 还没点 ▶ → 显示封面 + 大播放按钮
    if (!_playStarted) {
      final cover = _detail?.thumbnailUrl;
      return Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            color: Colors.black,
            child: cover != null && cover.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: cover,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) => const SizedBox.shrink(),
                  )
                : const SizedBox.shrink(),
          ),
          // 半透明遮罩,大 ▶ 按钮
          Material(
            color: Colors.black.withValues(alpha: 0.25),
            child: InkWell(
              onTap: _startPlayback,
              child: Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.play_arrow_rounded,
                      color: Colors.white, size: 56),
                ),
              ),
            ),
          ),
          _buildPlayerTopBar(),
        ],
      );
    }
    // 2) 已点 ▶ 但流还没就绪 → 封面 + spinner
    if (_streamLoading || _videoController == null) {
      final cover = _detail?.thumbnailUrl;
      return Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            color: Colors.black,
            child: cover != null && cover.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: cover,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) => const SizedBox.shrink(),
                  )
                : const SizedBox.shrink(),
          ),
          const Center(
            child: SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Colors.white,
              ),
            ),
          ),
          _buildPlayerTopBar(),
        ],
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Video(
          controller: _videoController!,
          subtitleViewConfiguration: const SubtitleViewConfiguration(
            style: TextStyle(
              height: 1.4,
              fontSize: 22,
              color: Colors.white,
              fontWeight: FontWeight.w500,
              shadows: [
                Shadow(blurRadius: 6, color: Colors.black87, offset: Offset(1, 1)),
              ],
            ),
            padding: EdgeInsets.fromLTRB(16, 0, 16, 36),
          ),
        ),
        YtVideoControls(
          player: _player!,
          title: _detail?.title ?? '加载中…',
          isFullscreen: _isFullscreen,
          onToggleFullscreen: _toggleFullscreen,
          fallbackDuration: _detail?.duration,
          qualities: _streams,
          currentQualityIdx: _currentQualityIdx,
          onSelectQuality: _switchQuality,
          subtitleTracks: _subtitleTracks,
          currentSubtitleIdx: _currentSubtitleIdx,
          currentTranslateLang: _currentTranslateLang,
          onSelectSubtitle: _setSubtitle,
          onSelectSubtitleTranslate: _setSubtitleTranslated,
        ),
      ],
    );
  }

  /// 视频区顶部 overlay: 返回按钮 + 标题 + 右上 YT 账号/登录
  Widget _buildPlayerTopBar() {
    final loggedIn = YtAuthService.isLoggedIn;
    final avatar = YtAuthService.avatarUrl;
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xB3000000), Colors.transparent],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 16),
        child: SafeArea(
          top: false,
          bottom: false,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new,
                    color: Colors.white, size: 20),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              Expanded(
                child: Text(
                  _detail?.title ?? '加载中…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
              // YT 登录入口/头像
              IconButton(
                tooltip: loggedIn ? 'YouTube 账号' : '登录 YouTube',
                icon: loggedIn && avatar != null && avatar.isNotEmpty
                    ? CircleAvatar(
                        radius: 14,
                        backgroundImage: CachedNetworkImageProvider(avatar),
                      )
                    : Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: loggedIn
                              ? const Color(0xFFFF0000)
                              : Colors.white24,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          loggedIn ? Icons.person : Icons.login,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                onPressed: () async {
                  await Get.toNamed<bool>('/ytLogin');
                  if (mounted) setState(() {});
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 全屏: 视频铺满整屏,无 TabBar 无 SafeArea(immersive 自处理)
    if (_isFullscreen) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.expand(child: _buildPlayerArea()),
      );
    }
    // 竖屏: 视频 16:9 顶部 + Tab 区
    return Scaffold(
      // 不要 AppBar — controls overlay 顶部条已含返回 + 标题,避免重复
      backgroundColor: Colors.black,
      body: SafeArea(
        top: true,
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(aspectRatio: 16 / 9, child: _buildPlayerArea()),
            TabBar(
              controller: _tabCtr,
              labelStyle:
                  TabBarTheme.of(context).labelStyle?.copyWith(fontSize: 13) ??
                  const TextStyle(fontSize: 13),
              labelPadding: const EdgeInsets.symmetric(horizontal: 14.0),
              tabs: const [
                Tab(text: '简介'),
                Tab(text: '评论'),
              ],
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              dividerColor: Colors.transparent,
              dividerHeight: 0,
            ),
            Expanded(
              child: TabBarView(
                controller: _tabCtr,
                children: [
                  _buildIntro(theme),
                  YtCommentsView(videoId: _videoId),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIntro(ThemeData theme) {
    if (_detailLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_detail == null) {
      return const Center(child: Text('简介加载失败'));
    }
    final detail = _detail!;
    final autoTrans = GStorage.setting
        .get(SettingBoxKey.ytAutoTranslateMeta, defaultValue: false) as bool;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          YtTranslatableText(
            text: detail.title,
            style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  height: 1.35,
                ) ??
                const TextStyle(fontWeight: FontWeight.bold),
            autoTranslate: autoTrans,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (detail.author.isNotEmpty)
                Text(
                  detail.author,
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.primary,
                  ),
                ),
              if (detail.uploadDate != null)
                Text(
                  _formatDate(detail.uploadDate!),
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              if (detail.duration != null)
                Text(
                  _formatDuration(detail.duration!),
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              if (detail.viewCount != null)
                Text(
                  '${_formatCount(detail.viewCount!)} 次观看',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          if (detail.description.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),
            YtTranslatableText(
              text: detail.description,
              style: TextStyle(
                fontSize: 13,
                height: 1.55,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: _descExpanded ? null : 3,
              overflow: _descExpanded ? null : TextOverflow.ellipsis,
              autoTranslate: autoTrans,
            ),
            if (!_descExpanded)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _descExpanded = true),
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '展开',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
          if (detail.keywords.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildTags(theme, detail.keywords),
          ],
          const SizedBox(height: 18),
          _actionsRow(theme, detail),
        ],
      ),
    );
  }

  Widget _buildTags(ThemeData theme, List<String> tags) {
    const collapsedCount = 6;
    // 显示用 tag 列表:已翻译时用译文,否则用原文
    final source = _translatedKeywords ?? tags;
    final showAll = _tagsExpanded || source.length <= collapsedCount;
    final visible = showAll ? source : source.take(collapsedCount).toList();
    final hasMore = source.length > collapsedCount;
    final hasTrans = _translatedKeywords != null;
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final k in visible) _tagChip(theme, k),
        if (hasMore)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _tagsExpanded = !_tagsExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              child: Text(
                _tagsExpanded ? '收起' : '展开 (${source.length})',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        // 翻译 / 显示原文 切换按钮
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _translatingTags
              ? null
              : () => hasTrans
                  ? setState(() => _translatedKeywords = null)
                  : _translateTags(tags),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  hasTrans ? Icons.format_quote : Icons.translate,
                  size: 12,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 3),
                Text(
                  _translatingTags
                      ? '翻译中…'
                      : (hasTrans ? '显示原文' : '翻译标签'),
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _translateTags(List<String> tags) async {
    if (_translatingTags) return;
    setState(() => _translatingTags = true);
    try {
      final translated =
          await YtTranslateService.instance.translateMany(tags);
      if (!mounted) return;
      setState(() {
        _translatedKeywords = translated;
        _translatingTags = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _translatingTags = false);
      SmartDialog.showToast('翻译标签失败:$e');
    }
  }

  Widget _tagChip(ThemeData theme, String text) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          '#$text',
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _actionsRow(ThemeData theme, YtVideoDetail detail) {
    Future<bool> ensureLogin(String action) async {
      if (!YtAuthService.isLoggedIn) {
        SmartDialog.showToast('需先登录 YouTube 才能$action');
        await Get.toNamed<bool>('/ytLogin');
        if (mounted) setState(() {});
        return YtAuthService.isLoggedIn;
      }
      return true;
    }

    Future<void> handleLike() async {
      if (!await ensureLogin('点赞')) return;
      try {
        if (_likeStatus == YtLikeStatus.liked) {
          await YtLikeService.instance.removeRating(_videoId);
          setState(() => _likeStatus = YtLikeStatus.none);
          SmartDialog.showToast('已取消点赞');
        } else {
          await YtLikeService.instance.like(_videoId);
          setState(() => _likeStatus = YtLikeStatus.liked);
          SmartDialog.showToast('已点赞');
        }
      } catch (e) {
        SmartDialog.showToast('点赞失败:$e');
      }
    }

    Future<void> handleDislike() async {
      if (!await ensureLogin('点踩')) return;
      try {
        if (_likeStatus == YtLikeStatus.disliked) {
          await YtLikeService.instance.removeRating(_videoId);
          setState(() => _likeStatus = YtLikeStatus.none);
          SmartDialog.showToast('已取消点踩');
        } else {
          await YtLikeService.instance.dislike(_videoId);
          setState(() => _likeStatus = YtLikeStatus.disliked);
          SmartDialog.showToast('已点踩');
        }
      } catch (e) {
        SmartDialog.showToast('点踩失败:$e');
      }
    }

    final liked = _likeStatus == YtLikeStatus.liked;
    final disliked = _likeStatus == YtLikeStatus.disliked;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _actionBtn(
          theme,
          liked ? Icons.thumb_up : Icons.thumb_up_outlined,
          detail.likeCount == null ? '点赞' : _formatCount(detail.likeCount!),
          handleLike,
          color: liked ? theme.colorScheme.primary : null,
        ),
        _actionBtn(
          theme,
          disliked ? Icons.thumb_down : Icons.thumb_down_outlined,
          '点踩',
          handleDislike,
          color: disliked ? theme.colorScheme.primary : null,
        ),
        _actionBtn(theme, Icons.star_border, '收藏', () async {
          if (!await ensureLogin('收藏')) return;
          SmartDialog.showToast('收藏 API 暂未对接');
        }),
        _actionBtn(theme, Icons.share_outlined, '分享', () {
          SmartDialog.showToast('已复制视频链接');
        }),
      ],
    );
  }

  Widget _actionBtn(
      ThemeData theme, IconData icon, String label, VoidCallback onTap,
      {Color? color}) {
    final tint = color ?? theme.colorScheme.onSurfaceVariant;
    // 用 GestureDetector + behavior=opaque 替代 InkWell
    // InkWell 需要 Material 父级且热区被 onSurface 干扰,真机/macOS 实测点不响应
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: tint),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: tint),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _formatCount(int n) {
    if (n >= 100000000) return '${(n / 100000000).toStringAsFixed(1)}亿';
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万';
    return '$n';
  }

}
