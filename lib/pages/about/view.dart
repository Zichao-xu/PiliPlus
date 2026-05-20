import 'dart:async';
import 'dart:io';

import 'package:PiliPlus/build_config.dart';
import 'package:PiliPlus/common/assets.dart';
import 'package:PiliPlus/common/constants.dart';
import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/dialog/dialog.dart';
import 'package:PiliPlus/common/widgets/dialog/export_import.dart';
import 'package:PiliPlus/common/widgets/flutter/list_tile.dart';
import 'package:PiliPlus/pages/mine/controller.dart';
import 'package:PiliPlus/services/logger.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/cache_manager.dart';
import 'package:PiliPlus/utils/date_utils.dart';
import 'package:PiliPlus/utils/device_utils.dart';
import 'package:PiliPlus/utils/extension/num_ext.dart';
import 'package:PiliPlus/utils/login_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/update.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:PiliPlus/utils/yt_auth.dart';
import 'package:PiliPlus/services/youtube/yt_innertube_player.dart';
import 'package:PiliPlus/services/youtube/yt_potoken_service.dart';
import 'package:flutter/material.dart' hide ListTile;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  final currentVersion =
      '${BuildConfig.versionName}+${BuildConfig.versionCode}';
  RxString cacheSize = ''.obs;

  late int _pressCount = 0;

  @override
  void initState() {
    super.initState();
    getCacheSize();
  }

  @override
  void dispose() {
    cacheSize.close();
    super.dispose();
  }

  void getCacheSize() {
    CacheManager.loadApplicationCache().then((res) {
      if (mounted) {
        cacheSize.value = CacheManager.formatSize(res);
      }
    });
  }

  void _showDialog() => showDialog(
    context: context,
    builder: (context) => AlertDialog(
      constraints: Style.dialogFixedConstraints,
      content: TextField(
        autofocus: true,
        onSubmitted: (value) {
          Get.back();
          if (value.isNotEmpty) {
            PageUtils.handleWebview(value, inApp: true);
          }
        },
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const style = TextStyle(fontSize: 15);
    final outline = theme.colorScheme.outline;
    final subTitleStyle = TextStyle(fontSize: 13, color: outline);
    final showAppBar = widget.showAppBar;
    final padding = MediaQuery.viewPaddingOf(context);
    return Scaffold(
      appBar: showAppBar ? AppBar(title: const Text('关于')) : null,
      resizeToAvoidBottomInset: false,
      body: ListView(
        padding: EdgeInsets.only(
          left: showAppBar ? padding.left : 0,
          right: showAppBar ? padding.right : 0,
          bottom: padding.bottom + 100,
        ),
        children: [
          GestureDetector(
            onTap: () {
              if (++_pressCount == 5) {
                _pressCount = 0;
                _showDialog();
              }
            },
            onSecondaryTap: PlatformUtils.isDesktop ? _showDialog : null,
            child: Image.asset(
              width: 150,
              height: 150,
              excludeFromSemantics: true,
              cacheWidth: 150.cacheSize(context),
              Assets.logo,
            ),
          ),
          ListTile(
            title: Text(
              Constants.appName,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium!.copyWith(height: 2),
            ),
            subtitle: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '使用Flutter开发的B站第三方客户端',
                  style: TextStyle(color: outline),
                  semanticsLabel: '与你一起，发现不一样的世界',
                ),
                const Icon(
                  Icons.accessibility_new,
                  semanticLabel: "无障碍适配",
                  size: 18,
                ),
              ],
            ),
          ),
          ListTile(
            onTap: () => Update.checkUpdate(false),
            onLongPress: () => Utils.copyText(currentVersion),
            onSecondaryTap: PlatformUtils.isMobile
                ? null
                : () => Utils.copyText(currentVersion),
            title: const Text('当前版本'),
            leading: const Icon(Icons.commit_outlined),
            trailing: Text(
              currentVersion,
              style: subTitleStyle,
            ),
          ),
          ListTile(
            title: Text(
              '''
Build Time: ${DateFormatUtils.format(BuildConfig.buildTime, format: DateFormatUtils.longFormatDs)}
Commit Hash: ${BuildConfig.commitHash}''',
              style: const TextStyle(fontSize: 14),
            ),
            leading: const Icon(Icons.info_outline),
            onTap: () => PageUtils.launchURL(
              '${Constants.sourceCodeUrl}/commit/${BuildConfig.commitHash}',
            ),
            onLongPress: () => Utils.copyText(BuildConfig.commitHash),
            onSecondaryTap: PlatformUtils.isMobile
                ? null
                : () => Utils.copyText(BuildConfig.commitHash),
          ),
          Divider(
            thickness: 1,
            height: 30,
            color: theme.colorScheme.outlineVariant,
          ),
          ListTile(
            onTap: () => PageUtils.launchURL(Constants.sourceCodeUrl),
            leading: const Icon(Icons.code),
            title: const Text('Source Code'),
            subtitle: Text(Constants.sourceCodeUrl, style: subTitleStyle),
          ),
          if (Platform.isAndroid)
            ListTile(
              onTap: () => Utils.channel.invokeMethod('linkVerifySettings'),
              leading: const Icon(MdiIcons.linkBoxOutline),
              title: const Text('打开受支持的链接'),
              trailing: Icon(
                Icons.arrow_forward,
                size: 16,
                color: outline,
              ),
            ),
          ListTile(
            onTap: () =>
                PageUtils.launchURL('${Constants.sourceCodeUrl}/issues'),
            leading: const Icon(Icons.feedback_outlined),
            title: const Text('问题反馈'),
            trailing: Icon(
              Icons.arrow_forward,
              size: 16,
              color: outline,
            ),
          ),
          ListTile(
            onTap: () => Get.toNamed('/logs'),
            onLongPress: LoggerUtils.clearLogs,
            onSecondaryTap: PlatformUtils.isMobile
                ? null
                : LoggerUtils.clearLogs,
            leading: const Icon(Icons.bug_report_outlined),
            title: const Text('错误日志'),
            subtitle: Text('长按清除日志', style: subTitleStyle),
            trailing: Icon(Icons.arrow_forward, size: 16, color: outline),
          ),
          ListTile(
            onTap: () {
              if (cacheSize.value.isNotEmpty) {
                showConfirmDialog(
                  context: context,
                  title: const Text('提示'),
                  content: const Text('该操作将清除图片及网络请求缓存数据，确认清除？'),
                  onConfirm: () async {
                    SmartDialog.showLoading(msg: '正在清除...');
                    try {
                      await CacheManager.clearLibraryCache();
                      SmartDialog.showToast('清除成功');
                    } catch (err) {
                      SmartDialog.showToast(err.toString());
                    } finally {
                      SmartDialog.dismiss();
                    }
                    getCacheSize();
                  },
                );
              }
            },
            leading: const Icon(Icons.delete_outline),
            title: const Text('清除缓存'),
            subtitle: Obx(
              () => Text(
                '图片及网络缓存 ${cacheSize.value}',
                style: subTitleStyle,
              ),
            ),
          ),
          ListTile(
            title: Text(YtAuthService.isLoggedIn
                ? 'YouTube 已登录${YtAuthService.userName != null ? ' (${YtAuthService.userName})' : ''}'
                : 'YouTube 登录'),
            leading: const Icon(Icons.smart_display_outlined),
            trailing: YtAuthService.isLoggedIn
                ? IconButton(
                    icon: const Icon(Icons.logout, size: 20),
                    tooltip: '退出 YouTube',
                    onPressed: () async {
                      await YtAuthService.logout();
                      if (context.mounted) (context as Element).markNeedsBuild();
                    },
                  )
                : null,
            onTap: YtAuthService.isLoggedIn
                ? null
                : () => Get.toNamed('/ytLogin'),
          ),
          ListTile(
            title: const Text('测试 PoToken + /player (调试)'),
            leading: const Icon(Icons.science_outlined),
            subtitle: const Text('mint poToken → /player → 列 1080p / 720p formats',
                style: TextStyle(fontSize: 11)),
            onTap: () async {
              SmartDialog.showLoading(msg: '初始化 PoToken 服务...');
              String? error;
              String? summary;
              try {
                // 1) ensure poToken can mint
                await YtPoTokenService.instance.initialize();
                // 2) call /player end-to-end
                SmartDialog.showLoading(msg: '调用 /player...');
                final resp = await YtInnertubePlayer.fetchPlayer('dQw4w9WgXcQ');
                final buf = StringBuffer();
                buf.writeln('visitorData=${resp.visitorData.substring(0, 32)}...');
                buf.writeln('hlsManifestUrl=${resp.hlsManifestUrl != null ? "yes" : "no"}');
                buf.writeln('durationMs=${resp.durationMs}');
                buf.writeln('formats(${resp.formats.length}):');
                for (final f in resp.formats) {
                  final v = f.hasVideo ? '${f.qualityLabel}/${f.width}x${f.height}@${f.fps ?? "?"}fps' : '-';
                  final a = f.hasAudio ? '${f.bitrate ~/ 1000}kbps${f.isDubbedAudio ? " (dubbed)" : ""}' : '-';
                  buf.writeln('  itag=${f.itag} ${f.container} ${f.codec} v=$v a=$a');
                }
                summary = buf.toString();
              } catch (e) {
                error = '$e';
              }
              SmartDialog.dismiss();
              if (!context.mounted) return;
              await showDialog<void>(
                context: context,
                builder: (dctx) => AlertDialog(
                  title: Text(error != null ? 'PoToken/Player 失败' : '✓ /player OK'),
                  content: SizedBox(
                    width: 600,
                    child: SingleChildScrollView(
                      child: SelectableText(
                        error ?? summary!,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 11),
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dctx),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              );
            },
          ),
          ListTile(
            title: const Text('导入/导出登录信息'),
            subtitle: const Text('Bilibili + YouTube 一起',
                style: TextStyle(fontSize: 11)),
            leading: const Icon(Icons.import_export_outlined),
            onTap: () => showImportExportDialog<Map>(
              context,
              title: '登录信息',
              localFileName: () => 'account',
              onExport: () {
                // 新格式:{ bilibili: {...accounts}, youtube: {...4 yt_auth keys} }
                final youtube = <String, dynamic>{};
                for (final k in const [
                  'yt_auth_cookies',
                  'yt_auth_user_name',
                  'yt_auth_avatar_url',
                  'yt_auth_channel_id',
                ]) {
                  final v = GStorage.localCache.get(k);
                  if (v != null) youtube[k] = v;
                }
                return Utils.jsonEncoder.convert({
                  'bilibili': Accounts.account.toMap(),
                  if (youtube.isNotEmpty) 'youtube': youtube,
                });
              },
              onImport: (json) async {
                // 新格式检测:顶层有 'bilibili' / 'youtube' key
                final isNewFmt = json.containsKey('bilibili') ||
                    json.containsKey('youtube');
                final biliMap = isNewFmt
                    ? (json['bilibili'] as Map?)
                    : json; // 旧格式整个 json 就是 B 站 mid -> LoginAccount
                final ytMap = isNewFmt ? (json['youtube'] as Map?) : null;

                if (biliMap != null && biliMap.isNotEmpty) {
                  final res = biliMap.map(
                    (key, value) =>
                        MapEntry(key, LoginAccount.fromJson(value as Map)),
                  );
                  await Accounts.account.putAll(res);
                  await Accounts.refresh();
                  MineController.anonymity.value = !Accounts.heartbeat.isLogin;
                  if (Accounts.main.isLogin) {
                    await LoginUtils.onLoginMain();
                  }
                }
                if (ytMap != null && ytMap.isNotEmpty) {
                  for (final entry in ytMap.entries) {
                    await GStorage.localCache.put(entry.key, entry.value);
                  }
                }
              },
            ),
          ),
          ListTile(
            title: const Text('导入/导出设置'),
            dense: false,
            leading: const Icon(Icons.import_export_outlined),
            onTap: () => showImportExportDialog<Map<String, dynamic>>(
              context,
              title: '设置',
              localFileName: () => 'setting_${DeviceUtils.platformName}',
              onExport: GStorage.exportAllSettings,
              onImport: (json) async {
                // 智能识别:若 JSON 顶层 key 全是 mid(纯数字 String)且 value 含 cookies/accessKey,
                // 这是登录信息备份,自动走登录信息导入路径(避免用户误用按钮被卡)
                final looksLikeAccount = json.isNotEmpty &&
                    json.entries.every(
                      (e) =>
                          int.tryParse(e.key) != null &&
                          e.value is Map &&
                          ((e.value as Map).containsKey('cookies') ||
                              (e.value as Map).containsKey('accessKey')),
                    );
                if (looksLikeAccount) {
                  final res = (json as Map).map(
                    (key, value) =>
                        MapEntry(key, LoginAccount.fromJson(value as Map)),
                  );
                  await Accounts.account.putAll(res);
                  await Accounts.refresh();
                  MineController.anonymity.value = !Accounts.heartbeat.isLogin;
                  if (Accounts.main.isLogin) {
                    await LoginUtils.onLoginMain();
                  }
                  SmartDialog.showToast('识别为登录信息备份,已按登录信息导入');
                  return;
                }
                await GStorage.importAllJsonSettings(json);
              },
            ),
          ),
          ListTile(
            title: const Text('重置所有设置'),
            leading: const Icon(Icons.settings_backup_restore_outlined),
            onTap: () => showDialog(
              context: context,
              builder: (context) {
                return SimpleDialog(
                  clipBehavior: Clip.hardEdge,
                  title: const Text('是否重置所有设置？'),
                  children: [
                    ListTile(
                      dense: true,
                      onTap: () async {
                        Get.back();
                        await Future.wait([
                          GStorage.setting.clear(),
                          GStorage.video.clear(),
                        ]);
                        SmartDialog.showToast('重置成功');
                      },
                      title: const Text('重置可导出的设置', style: style),
                    ),
                    ListTile(
                      dense: true,
                      onTap: () async {
                        Get.back();
                        await GStorage.clear();
                        SmartDialog.showToast('重置成功');
                      },
                      title: const Text('重置所有数据（含登录信息）', style: style),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
