// YT 视频播放器自定义控件层
// 视觉学 PiliPlus PlPlayer view widget(顶部/底部黑色渐变 overlay,
// Material icons,圆形按钮),功能为 YT MVP 子集:
// - 顶部: 返回 + 标题
// - 中央: buffering 转圈 / 单击切换可见性 / 双击 seek ±10s
// - 底部: 进度条 + 时间 + 倍速 + 全屏
// - 自动隐藏(3 秒不动)

import 'dart:async';

import 'package:PiliPlus/services/youtube/yt_video.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

class YtVideoControls extends StatefulWidget {
  const YtVideoControls({
    super.key,
    required this.player,
    required this.title,
    this.onBack,
    this.onToggleFullscreen,
    this.isFullscreen = false,
    this.fallbackDuration,
    this.qualities = const [],
    this.currentQualityIdx = 0,
    this.onSelectQuality,
    this.subtitleTracks = const [],
    this.currentSubtitleIdx = -1,
    this.currentTranslateLang,
    this.onSelectSubtitle,
    this.onSelectSubtitleTranslate,
  });

  final Player player;
  final String title;
  final VoidCallback? onBack;
  final VoidCallback? onToggleFullscreen;
  final bool isFullscreen;
  // media_kit.player.stream.duration 在 YT URL 上可能持续返回 0;
  // 这时退到上游 yt_explode_dart 提供的元数据时长,避免 slider 不可拖
  final Duration? fallbackDuration;
  // 画质切换 — qualities 由父级 page 持有,YT muxed 流列表
  final List<YtMuxedStreamOption> qualities;
  final int currentQualityIdx;
  final ValueChanged<int>? onSelectQuality;
  // 字幕 — subtitleTracks 由父级 page 持有;-1 表示关闭
  final List<YtSubtitleTrackInfo> subtitleTracks;
  final int currentSubtitleIdx;
  /// 当前翻译目标语言代码(null = 显示原 track 不翻译)
  final String? currentTranslateLang;
  final ValueChanged<int>? onSelectSubtitle;
  /// (nativeIdx, targetLangCode, targetLangName) 触发翻译
  final void Function(int nativeIdx, String tlang, String tlangName)?
      onSelectSubtitleTranslate;

  @override
  State<YtVideoControls> createState() => _YtVideoControlsState();
}

class _YtVideoControlsState extends State<YtVideoControls>
    with SingleTickerProviderStateMixin {
  bool _visible = true;
  Timer? _hideTimer;
  late final AnimationController _fadeCtr;
  late final Animation<double> _fade;

  // Player 状态镜像
  bool _playing = false;
  bool _buffering = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffer = Duration.zero;
  double _rate = 1.0;

  // 拖拽中暂存位置(避免 seek 期间 position 流回弹回去)
  Duration? _dragPosition;

  final List<StreamSubscription> _subs = [];

  static const _speedOptions = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  @override
  void initState() {
    super.initState();
    _fadeCtr = AnimationController(
      duration: const Duration(milliseconds: 180),
      vsync: this,
      value: 1.0,
    );
    _fade = CurvedAnimation(parent: _fadeCtr, curve: Curves.easeOut);
    _scheduleHide();

    // 立即同步当前 player state — 避免 controls 刚 mount 时按钮显示错位
    // (yt_video_page 父级一直在播时,_playing=false 让按钮显示 ▶,实际应该是 ‖)
    _playing = widget.player.state.playing;
    _position = widget.player.state.position;
    _duration = widget.player.state.duration;
    _buffer = widget.player.state.buffer;

    _subs
      ..add(widget.player.stream.playing.listen((v) {
        if (mounted) setState(() => _playing = v);
      }))
      ..add(widget.player.stream.buffering.listen((v) {
        if (mounted) setState(() => _buffering = v);
      }))
      ..add(widget.player.stream.position.listen((v) {
        if (mounted && _dragPosition == null) setState(() => _position = v);
      }))
      ..add(widget.player.stream.duration.listen((v) {
        if (mounted) setState(() => _duration = v);
      }))
      ..add(widget.player.stream.buffer.listen((v) {
        if (mounted) setState(() => _buffer = v);
      }));
    // rate 没有 stream,只能命令式同步: 在 _setRate 时手动 setState
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _hideTimer?.cancel();
    _fadeCtr.dispose();
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _playing) _setVisible(false);
    });
  }

  void _setVisible(bool v) {
    if (_visible == v) return;
    setState(() => _visible = v);
    if (v) {
      _fadeCtr.forward();
      _scheduleHide();
    } else {
      _fadeCtr.reverse();
    }
  }

  void _onTap() {
    _setVisible(!_visible);
  }

  Duration get _effectiveDuration =>
      _duration.inMilliseconds > 0 ? _duration : (widget.fallbackDuration ?? Duration.zero);

  void _onDoubleTapLeft() {
    final to = _position - const Duration(seconds: 10);
    widget.player.seek(to.isNegative ? Duration.zero : to);
    HapticFeedback.lightImpact();
  }

  void _onDoubleTapRight() {
    final dur = _effectiveDuration;
    final to = _position + const Duration(seconds: 10);
    widget.player.seek(dur > Duration.zero && to > dur ? dur : to);
    HapticFeedback.lightImpact();
  }

  void _onDoubleTapCenter() {
    _togglePlay();
    HapticFeedback.lightImpact();
  }

  Future<void> _togglePlay() async {
    // 直读 player.state 避免镜像 lag(stream emit 慢于实际状态变化)
    final actuallyPlaying = widget.player.state.playing;
    if (actuallyPlaying) {
      await widget.player.pause();
    } else {
      await widget.player.play();
    }
    // 立即 set mirror 避免 stream emit 延迟时按钮显示错位
    if (mounted) setState(() => _playing = !actuallyPlaying);
    _scheduleHide();
  }

  void _showSubtitleSheet() {
    final tracks = widget.subtitleTracks;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return SafeArea(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.6,
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
                    child: Text('字幕',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold)),
                  ),
                  ListTile(
                    dense: true,
                    title: const Text('关闭'),
                    trailing: widget.currentSubtitleIdx < 0
                        ? Icon(Icons.check,
                            color: Theme.of(context).colorScheme.primary)
                        : null,
                    onTap: () {
                      widget.onSelectSubtitle?.call(-1);
                      Navigator.pop(context);
                    },
                  ),
                  if (tracks.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
                      child: Text('原始语言',
                          style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ),
                    for (var i = 0; i < tracks.length; i++)
                      ListTile(
                        dense: true,
                        title: Text(tracks[i].label),
                        trailing: i == widget.currentSubtitleIdx &&
                                widget.currentTranslateLang == null
                            ? Icon(Icons.check,
                                color: Theme.of(context).colorScheme.primary)
                            : null,
                        onTap: () {
                          widget.onSelectSubtitle?.call(i);
                          Navigator.pop(context);
                        },
                      ),
                  ],
                  if (tracks.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
                      child: Text('自动翻译为',
                          style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ),
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.translate, size: 18),
                      title: const Text('选择目标语言...'),
                      onTap: () {
                        Navigator.pop(context);
                        _showTranslateSheet();
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showTranslateSheet() {
    final tracks = widget.subtitleTracks;
    if (tracks.isEmpty) return;
    // 用当前选中 native track,否则用第一条
    final baseIdx =
        widget.currentSubtitleIdx >= 0 ? widget.currentSubtitleIdx : 0;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return SafeArea(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.7,
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                    child: Text(
                      '翻译 「${tracks[baseIdx].label}」 为',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ),
                  for (final t in YtVideoService.translateTargets)
                    ListTile(
                      dense: true,
                      title: Text(t.name),
                      subtitle: Text(t.code,
                          style: const TextStyle(
                              fontSize: 10, color: Colors.grey)),
                      trailing: widget.currentTranslateLang == t.code
                          ? Icon(Icons.check,
                              color: Theme.of(context).colorScheme.primary)
                          : null,
                      onTap: () {
                        widget.onSelectSubtitleTranslate
                            ?.call(baseIdx, t.code, t.name);
                        Navigator.pop(context);
                      },
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showQualitySheet() {
    final qs = widget.qualities;
    if (qs.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return SafeArea(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: ListView(
              shrinkWrap: true,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
                  child: Text('画质',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                ),
                for (var i = 0; i < qs.length; i++)
                  ListTile(
                    dense: true,
                    title: Text(qs[i].qualityLabel),
                    trailing: i == widget.currentQualityIdx
                        ? Icon(Icons.check,
                            color: Theme.of(context).colorScheme.primary)
                        : null,
                    onTap: () {
                      widget.onSelectQuality?.call(i);
                      Navigator.pop(context);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSpeedSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return SafeArea(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: ListView(
              shrinkWrap: true,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
                  child: Text('倍速',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                ),
                for (final s in _speedOptions)
                  ListTile(
                    dense: true,
                    title: Text('${s.toStringAsFixed(s == s.roundToDouble() ? 1 : 2)}x'),
                    trailing: (_rate - s).abs() < 0.01
                        ? Icon(Icons.check,
                            color: Theme.of(context).colorScheme.primary)
                        : null,
                    onTap: () {
                      widget.player.setRate(s);
                      if (mounted) setState(() => _rate = s);
                      Navigator.pop(context);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 手势层(透明,接管点击): 三分屏 — 左 1/3 双击后退 10s,
        // 中 1/3 双击切暂停,右 1/3 双击前进 10s;任一处单击切换 overlay 可见
        Positioned.fill(
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _onTap,
                  onDoubleTap: _onDoubleTapLeft,
                ),
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _onTap,
                  onDoubleTap: _onDoubleTapCenter,
                ),
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _onTap,
                  onDoubleTap: _onDoubleTapRight,
                ),
              ),
            ],
          ),
        ),
        // buffering 中央 spinner(始终可见,不受 _visible 控制)
        if (_buffering)
          const Center(
            child: SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
            ),
          ),
        // 顶部 / 底部 overlay
        FadeTransition(
          opacity: _fade,
          child: IgnorePointer(
            ignoring: !_visible,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildTopBar(),
                // 中央暂停按钮已移除: 单击只显隐 overlay,
                // 切换暂停统一用底部按钮 + 中央双击
                _buildBottomBar(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTopBar() {
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
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
              onPressed: widget.onBack ?? () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: SizedBox(
                height: 22,
                child: _MarqueeText(
                  text: widget.title,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              icon: const Icon(Icons.share_outlined,
                  color: Colors.white, size: 20),
              tooltip: '分享',
              onPressed: () {
                Clipboard.setData(
                    ClipboardData(text: 'https://youtu.be/${_extractIdFromTitle()}'));
                _toast('已复制视频链接');
              },
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              icon: const Icon(Icons.more_vert, color: Colors.white, size: 20),
              tooltip: '更多',
              onPressed: () => _toast('更多功能开发中'),
            ),
          ],
        ),
        ),
      ),
    );
  }

  String _extractIdFromTitle() {
    // 简单实现: 由外部传 videoId 更稳,这里 fallback 用 title 不可解,
    // 先返回空让 share 文案至少是 youtu.be 域名;后续可通过 widget 参数传 videoId
    return '';
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  Widget _buildBottomBar() {
    final pos = _dragPosition ?? _position;
    final total = _effectiveDuration;
    final hasDur = total.inMilliseconds > 0;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Color(0xCC000000), Colors.transparent],
          ),
        ),
        padding: const EdgeInsets.only(left: 4, right: 4, top: 24),
        child: SafeArea(
          top: false,
          bottom: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 20,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // 已缓冲层(白 alpha 50%),用 Slider 的横向 padding 对齐 thumb 行程
                    LayoutBuilder(
                      builder: (context, c) {
                        // Slider 内部左右各预留约 12px 给 overlay/thumb,这里用同样的内边距
                        const sideGutter = 12.0;
                        final usable = (c.maxWidth - sideGutter * 2)
                            .clamp(0.0, double.infinity);
                        final factor = hasDur
                            ? (_buffer.inMilliseconds /
                                    total.inMilliseconds)
                                .clamp(0.0, 1.0)
                            : 0.0;
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: sideGutter),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              width: usable * factor,
                              height: 2.5,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2.5,
                        thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 5),
                        overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 10),
                        activeTrackColor: Colors.white,
                        inactiveTrackColor: Colors.white24,
                        thumbColor: Colors.white,
                        overlayColor: Colors.white24,
                      ),
                      child: Slider(
                  min: 0,
                  max: hasDur
                      ? total.inMilliseconds.toDouble()
                      : 1,
                  value: pos.inMilliseconds
                      .toDouble()
                      .clamp(0,
                          hasDur ? total.inMilliseconds.toDouble() : 1),
                  onChanged: !hasDur
                      ? null
                      : (v) {
                          setState(() {
                            _dragPosition =
                                Duration(milliseconds: v.toInt());
                          });
                        },
                  onChangeEnd: !hasDur
                      ? null
                      : (v) async {
                          final target = Duration(milliseconds: v.toInt());
                          await widget.player.seek(target);
                          if (!mounted) return;
                          setState(() {
                            _position = target;
                            _dragPosition = null;
                          });
                          _scheduleHide();
                        },
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 36,
                child: Row(
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      icon: Icon(_playing ? Icons.pause : Icons.play_arrow,
                          color: Colors.white, size: 24),
                      onPressed: _togglePlay,
                    ),
                    Text(
                      '${_fmt(pos)} / ${_fmt(total)}',
                      style:
                          const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    const Spacer(),
                    if (widget.subtitleTracks.isNotEmpty)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding:
                            const EdgeInsets.symmetric(horizontal: 6),
                        icon: Icon(
                          widget.currentSubtitleIdx >= 0
                              ? Icons.subtitles
                              : Icons.subtitles_outlined,
                          color: Colors.white,
                          size: 20,
                        ),
                        onPressed: _showSubtitleSheet,
                      ),
                    if (widget.qualities.isNotEmpty)
                      TextButton(
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 32),
                          padding:
                              const EdgeInsets.symmetric(horizontal: 6),
                        ),
                        onPressed: _showQualitySheet,
                        child: Text(
                          widget.qualities[widget.currentQualityIdx]
                              .qualityLabel,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13),
                        ),
                      ),
                    TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 32),
                        padding:
                            const EdgeInsets.symmetric(horizontal: 6),
                      ),
                      onPressed: _showSpeedSheet,
                      child: Text(
                        '${_rate.toStringAsFixed(_rate == _rate.roundToDouble() ? 1 : 2)}x',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 13),
                      ),
                    ),
                    if (widget.onToggleFullscreen != null)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        icon: Icon(
                          widget.isFullscreen
                              ? Icons.fullscreen_exit
                              : Icons.fullscreen,
                          color: Colors.white,
                          size: 22,
                        ),
                        onPressed: widget.onToggleFullscreen,
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

  String _fmt(Duration d) => DurationUtils.formatDuration(d.inSeconds);
}

/// 自动滚动的单行文本:文本宽度超过容器时 marquee,否则静态显示
class _MarqueeText extends StatefulWidget {
  const _MarqueeText({required this.text, required this.style});
  final String text;
  final TextStyle style;
  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctr;

  @override
  void initState() {
    super.initState();
    _ctr = AnimationController(
      // 用文本估算秒数: 大约每 25px 1 秒
      duration: Duration(seconds: (widget.text.length * 0.4).clamp(8, 30).toInt()),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _ctr.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tp = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout();
        if (tp.width <= constraints.maxWidth) {
          return Align(
            alignment: Alignment.centerLeft,
            child: Text(widget.text, style: widget.style, maxLines: 1),
          );
        }
        const gap = 40.0;
        final totalShift = tp.width + gap;
        return ClipRect(
          child: AnimatedBuilder(
            animation: _ctr,
            builder: (context, _) {
              final dx = -totalShift * _ctr.value;
              return Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  Positioned(
                    left: dx,
                    top: 0,
                    bottom: 0,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(widget.text,
                              style: widget.style, maxLines: 1),
                        ),
                        const SizedBox(width: gap),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(widget.text,
                              style: widget.style, maxLines: 1),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
