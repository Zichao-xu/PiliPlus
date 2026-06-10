# 2026-06-11 Android 移植:YT 兼容 + 配置无损导入

## 目标(adams 指定)
1. 让 YouTube 第二视频源在 **Android** 上跑通(此前 fork 只编 iOS/TrollStore)。
2. iOS 端导出的配置文件能**无损导入 Android**。
无人值守模式完成(adams 睡前授权"手机自己调试,睡醒看结果")。

## 结论:两个目标均已真机验证通过(小米 M2006J10C / Android 12)

### 目标① YT 在 Android 跑通 ✅
- **poToken / BotGuard 在 Android Chromium WebView 工作**(最高危项,审计判定纸面无法定论、必须真机验证):关于页"测试 PoToken"→ `/player OK` + visitorData + **27 个 formats(144p–4K 2160p)**。
- **实际播放(VOD「90's Chill Lofi」)**:视频解码(piliplus CPU 64% + SurfaceView/BLAST 输出层)+ **音频播放**(AudioTrack `state:started` usage=USAGE_MEDIA/MOVIE,pid=piliplus)。取流无 403/异常。
- 混排搜索(B站蓝标 + YT 红标)、YT 详情页(标题/频道/观看/点赞/标签/翻译)、YT 设置页、YT 登录卡片全部正常渲染。
- 代码层零 `Platform.is*` 分支(审计确认),media_kit Android libmpv 库已接上。
- **遗留观察**:Lofi Girl 24/7 **直播流**(HLS live)首次测试未出音频(可能缓冲/直播特例);常规 VOD 音视频均正常。直播流音频待复测确认。

### 目标② 配置无损导入 ✅
- 用 2026-05-19 从 iOS/macOS 导出的真实配置 JSON(`piliplus_account_*.json`)实测:
  - **Bilibili 账号无损还原**:-CORISIKA- LV6,硬币/经验/关注/粉丝/收藏夹全部加载。
  - **YouTube 账号无损还原**:localcache.hive 含 yt_auth_cookies/SAPISID/__Secure;重启后显示「YouTube 已登录」。
  - **重启持久化**通过。
- 导出 JSON 是纯 JSON(bilibili + youtube 段),无平台字段/绝对路径/bundleid,跨平台天然兼容(审计已预判,真机坐实)。
- **小瑕疵**:导入后 YT 登录态未即时刷新 UI(显示未登录),重启即正常 → 可加导入后刷新 YT 状态。

## 构建之路(关键踩坑,均已解决)
1. **本机 Tahoe JVM 全崩**:macOS Tahoe 上 JDK17/21(homebrew+Temurin)启动即 `SIGBUS BUS_ADRALN`,本机 `flutter build apk` 死路 → 改 **GitHub Actions**(上游自带 `build.yml`,ubuntu runner)。
2. **依赖悬空**:`flutter pub get` 在 CI 干净环境失败——
   - `My-Responsitories/media-kit` 的 `version_1.2.5` 分支被 force-push,lock 锁的 `14c3ee41` 成悬空 commit(pub 不做 fetch-by-sha,按分支名拉够不到)。
   - `bggRGjQaUbCoE/floating` 仓库已 404;`flutter_chat_packages`、`flutter_file_picker` 分支 force-push 致 lock commit 悬空。
   - 解法:把这些不可达依赖 **vendor 到 `third_party/`** 改本地 path(media-kit 6 包 + floating + chat_bottom_container + file_picker);其余可达 fork 保持 git。本地用干净 PUB_CACHE + `pub.flutter-io.cn` 镜像复现验证。
3. **asset 缺失**:`default_account.json`(被 .gitignore,含真实账号)pubspec 残留声明导致 bundle 失败 → 移除声明(lib 本就不引用,仅 default_settings.json 被 storage.dart 读)。
4. **artifact 平铺**:upload-artifact 把 apk 平铺成内容树无法直接装 → 走 **GitHub Release** 取原始 apk。

## 产物
- 分支 `ci/vendor-broken-forks`(已 push,含所有修复 + vendored 源码)。
- GitHub Release `android-yt-test`:3 个 ABI 的 APK(arm64/armv7/x86_64)。
- 本机 `~/PiliPlus-apk-ci/PiliPlus_android_2.0.7-c25422440+4955_arm64-v8a.apk`(24MB,debug 签名,已装小米)。
- 版本 `2.0.7-c25422440`。

## 待 adams 决策 / 待办
- [ ] 是否把 `ci/vendor-broken-forks` 合并到 main(含 third_party vendored,~5MB)。
- [ ] 直播流音频复测(常规 VOD 已正常)。
- [ ] 导入后刷新 YT 登录 UI(小 UX)。
- [ ] 如需正式签名,配 `android/key.properties` + secret(当前 debug 签名,自用够)。
- [ ] CI artifact 平铺问题:upload-artifact 的 `archive: false` 导致,可改用 release 或修 workflow。
