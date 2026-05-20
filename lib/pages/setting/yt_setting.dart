// YouTube 设置 — 画质/字幕/翻译 / DeepL API key
//
// 数据存 GStorage.setting,key 见 [SettingBoxKey] ytXxx 段。
// 翻译相关与 #6 翻译功能(标题/简介/评论/tag)共享这里的 key。

import 'package:PiliPlus/common/widgets/flutter/list_tile.dart';
import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter/material.dart' hide ListTile;
import 'package:hive_ce/hive.dart';

class YtSetting extends StatefulWidget {
  const YtSetting({super.key, this.showAppBar = true});
  final bool showAppBar;

  @override
  State<YtSetting> createState() => _YtSettingState();
}

class _YtSettingState extends State<YtSetting> {
  Box<dynamic> get _box => GStorage.setting;

  static const _qualityOptions = ['auto', '360p', '720p', '1080p'];
  // DeepL 支持的目标语言(常用 25 个,DeepL Free 全部支持)
  static const _translateTargets = <({String code, String label})>[
    (code: 'ZH-HANS', label: '中文(简体)'),
    (code: 'ZH-HANT', label: '中文(繁體)'),
    (code: 'EN', label: 'English'),
    (code: 'JA', label: '日本語'),
    (code: 'KO', label: '한국어'),
    (code: 'ES', label: 'Español'),
    (code: 'FR', label: 'Français'),
    (code: 'DE', label: 'Deutsch'),
    (code: 'RU', label: 'Русский'),
    (code: 'PT-BR', label: 'Português'),
    (code: 'IT', label: 'Italiano'),
    (code: 'AR', label: 'العربية'),
    (code: 'TR', label: 'Türkçe'),
    (code: 'VI', label: 'Tiếng Việt'),
    (code: 'TH', label: 'ไทย'),
    (code: 'ID', label: 'Bahasa Indonesia'),
    (code: 'PL', label: 'Polski'),
    (code: 'NL', label: 'Nederlands'),
    (code: 'SV', label: 'Svenska'),
  ];
  // 翻译服务商:固定走 MyMemory anonymous(免 key),不暴露选项

  // 读取(带默认值)
  String get _quality =>
      _box.get(SettingBoxKey.ytDefaultQuality, defaultValue: 'auto') as String;
  String get _subtitleDefault =>
      _box.get(SettingBoxKey.ytSubtitleDefault, defaultValue: 'native')
          as String;
  String get _subtitleTranslateLang =>
      _box.get(SettingBoxKey.ytSubtitleTranslateLang, defaultValue: 'zh-Hans')
          as String;
  bool get _autoTranslateMeta =>
      _box.get(SettingBoxKey.ytAutoTranslateMeta, defaultValue: false) as bool;
  String get _targetLang =>
      _box.get(SettingBoxKey.ytTranslateTargetLang, defaultValue: 'ZH-HANS')
          as String;

  Future<void> _put(String key, dynamic value) async {
    await _box.put(key, value);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final body = ViewSafeArea(
      child: ListView(
        children: [
          _section('播放'),
          ListTile(
            leading: const Icon(Icons.high_quality_outlined),
            title: const Text('默认画质'),
            subtitle: Text(_quality == 'auto' ? '自动(HLS 无缝切换)' : _quality),
            onTap: () => _pickRadio(
              context,
              title: '默认画质',
              current: _quality,
              options: _qualityOptions
                  .map((q) => (
                        code: q,
                        label: q == 'auto' ? '自动(HLS 无缝切换)' : q,
                      ))
                  .toList(),
              onChanged: (v) => _put(SettingBoxKey.ytDefaultQuality, v),
            ),
          ),
          _section('字幕'),
          ListTile(
            leading: const Icon(Icons.subtitles_outlined),
            title: const Text('默认字幕'),
            subtitle: Text(switch (_subtitleDefault) {
              'off' => '关闭',
              'native' => '原始语言(若有)',
              'translate' => '自动翻译为 $_subtitleTranslateLang',
              _ => _subtitleDefault,
            }),
            onTap: () => _pickRadio(
              context,
              title: '默认字幕',
              current: _subtitleDefault,
              options: const [
                (code: 'off', label: '关闭'),
                (code: 'native', label: '原始语言(若有)'),
                (code: 'translate', label: '自动翻译'),
              ],
              onChanged: (v) => _put(SettingBoxKey.ytSubtitleDefault, v),
            ),
          ),
          if (_subtitleDefault == 'translate')
            ListTile(
              leading: const Icon(Icons.translate),
              title: const Text('字幕翻译目标语言'),
              subtitle: Text(_subtitleTranslateLang),
              onTap: () => _pickRadio(
                context,
                title: '字幕翻译目标',
                current: _subtitleTranslateLang,
                options: const [
                  (code: 'zh-Hans', label: '中文(简体)'),
                  (code: 'zh-Hant', label: '中文(繁體)'),
                  (code: 'en', label: 'English'),
                  (code: 'ja', label: '日本語'),
                  (code: 'ko', label: '한국어'),
                ],
                onChanged: (v) =>
                    _put(SettingBoxKey.ytSubtitleTranslateLang, v),
              ),
            ),
          _section('翻译(标题 / 简介 / 评论 / Tag)'),
          SwitchListTile(
            secondary: const Icon(Icons.auto_awesome_outlined),
            title: const Text('自动翻译'),
            subtitle: const Text('打开 YT 视频时自动翻译元数据'),
            value: _autoTranslateMeta,
            onChanged: (v) => _put(SettingBoxKey.ytAutoTranslateMeta, v),
          ),
          ListTile(
            leading: const Icon(Icons.language),
            title: const Text('翻译目标语言'),
            subtitle: Text(_translateTargets
                    .firstWhere(
                      (e) => e.code == _targetLang,
                      orElse: () => _translateTargets.first,
                    )
                    .label),
            onTap: () => _pickRadio(
              context,
              title: '翻译目标语言',
              current: _targetLang,
              options: _translateTargets,
              onChanged: (v) => _put(SettingBoxKey.ytTranslateTargetLang, v),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline,
                color: Colors.amber, size: 18),
            dense: true,
            title: const Text(
                '翻译服务:MyMemory (anonymous,免 key,1000 字/天/IP)',
                style: TextStyle(fontSize: 12)),
            subtitle: const Text(
                '超额度会失败,稍后重试或换节点',
                style: TextStyle(fontSize: 11)),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );

    if (!widget.showAppBar) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('YouTube 设置')),
      body: body,
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      );

  Future<void> _pickRadio(
    BuildContext context, {
    required String title,
    required String current,
    required List<({String code, String label})> options,
    required ValueChanged<String> onChanged,
  }) async {
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(title),
        children: [
          for (final o in options)
            RadioListTile<String>(
              value: o.code,
              groupValue: current,
              onChanged: (v) => Navigator.pop(ctx, v),
              title: Text(o.label),
            ),
        ],
      ),
    );
    if (selected != null && selected != current) {
      onChanged(selected);
    }
  }

}
