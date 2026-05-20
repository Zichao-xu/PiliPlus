// X 风格"翻译按钮"包装 — 显示原文 / 译文 + 切换链接
//
// 用法:
//   YtTranslatableText(text: detail.title, style: titleStyle)
// 也可以通过 [autoTranslate] 让 widget 初始就先调一次翻译(读全局开关时用)。

import 'package:PiliPlus/services/youtube/yt_translate_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

class YtTranslatableText extends StatefulWidget {
  const YtTranslatableText({
    super.key,
    required this.text,
    this.style,
    this.maxLines,
    this.overflow,
    this.selectable = false,
    this.autoTranslate = false,
    this.targetLang,
  });

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool selectable;
  final bool autoTranslate;
  final String? targetLang;

  @override
  State<YtTranslatableText> createState() => _YtTranslatableTextState();
}

class _YtTranslatableTextState extends State<YtTranslatableText> {
  String? _translated;
  bool _loading = false;
  bool _showOriginal = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoTranslate && YtTranslateService.instance.isConfigured) {
      _doTranslate();
    }
  }

  @override
  void didUpdateWidget(covariant YtTranslatableText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      // 原文换了,清缓存重新走 auto 流程
      _translated = null;
      _showOriginal = false;
      if (widget.autoTranslate && YtTranslateService.instance.isConfigured) {
        _doTranslate();
      }
    }
  }

  Future<void> _doTranslate() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final t = await YtTranslateService.instance.translate(
        widget.text,
        targetLang: widget.targetLang,
      );
      if (!mounted) return;
      setState(() {
        _translated = t;
        _loading = false;
        _showOriginal = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      SmartDialog.showToast('翻译失败:$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasTranslation = _translated != null;
    final showingOriginal = !hasTranslation || _showOriginal;
    final displayText = showingOriginal ? widget.text : _translated!;

    final textWidget = widget.selectable
        ? SelectableText(
            displayText,
            style: widget.style,
            maxLines: widget.maxLines,
          )
        : Text(
            displayText,
            style: widget.style,
            maxLines: widget.maxLines,
            overflow: widget.overflow,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        textWidget,
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!hasTranslation)
              _miniBtn(
                theme,
                icon: _loading ? null : Icons.translate,
                label: _loading ? '翻译中…' : '翻译',
                onTap: _loading ? null : _doTranslate,
              )
            else if (showingOriginal)
              _miniBtn(
                theme,
                icon: Icons.translate,
                label: '显示译文',
                onTap: () => setState(() => _showOriginal = false),
              )
            else
              _miniBtn(
                theme,
                icon: Icons.format_quote,
                label: '显示原文',
                onTap: () => setState(() => _showOriginal = true),
              ),
            if (hasTranslation && !showingOriginal)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Text(
                  'DeepL',
                  style: TextStyle(
                    fontSize: 10,
                    color: theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.6),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _miniBtn(ThemeData theme,
      {IconData? icon, required String label, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: theme.colorScheme.primary),
              const SizedBox(width: 3),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
