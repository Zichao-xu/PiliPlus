# 2026-05-19 Phase A 4 项 mac 自测全部 PASS

## 前置:computer-use dock fix

用户在另一会话定位到 macOS Tahoe Dock layer=20 全屏覆盖窗口拦截 hit-test 根因,fix:
```bash
defaults write com.apple.dock autohide -bool true
killall Dock
```
详见 [reference_macos_computer_use_stuck.md](../../../../.claude/projects/-Users-adams/memory/reference_macos_computer_use_stuck.md)。

应用后 computer-use 所有 click 即刻通过。

## 自测结果

### ✅ #5 YouTube 设置面板

入口:**设置 → YouTube 设置 - 画质、字幕、翻译(DeepL)、API Key**(列表第 7 项)

进入后看到完整 6 个选项:
- **播放**:默认画质 `自动(HLS 无缝切换)`(默认)— Radio dialog 4 个选项齐全(auto/360p/720p/1080p)
- **字幕**:默认字幕 `原始语言(若有)`
- **翻译(标题/简介/评论/Tag)**:
  - 自动翻译 toggle(默认 off)
  - 翻译目标语言 `中文(简体)`
  - 翻译服务商 `DeepL Free (500K 字/月)`
  - DeepL API Key `未设置(点击输入)`
- DeepL Free 注册:https://www.deepl.com/pro-api 提示行

布局、对齐、默认值加载、Radio 交互全部正常。

### ✅ #4 cookie 合并导出与 B 站

入口:**关于 → 导入/导出登录信息 - Bilibili + YouTube 一起**

点击 → 弹"导出至剪贴板/导出文件至本地/输入/从剪贴板导入/从本地文件导入"6 选项 dialog。
点 "导出至剪贴板" → pbpaste 验证:
```
JSON 顶层 keys: ['bilibili', 'youtube']
bilibili 类型: dict 条数: 0  (mac 没 B 站登录)
youtube 类型: dict keys: ['yt_auth_cookies']
总字节: 1724
```

新 schema 完美工作,旧格式 fallback dart 已单测 PASS(`scratch/test_phaseA_logic.dart`)。

### ✅ #6 翻译按钮 UI(X 风格)

进 Rick Astley YT 视频详情页,看到:
- **标题下方** `Aa 翻译` 蓝字小按钮(原文 + 译文切换入口)
- **简介下方** `Aa 翻译` 蓝字按钮 + `展开` 按钮(继承之前简介折叠)
- **Tags 区**:`#tag1 #tag2 ... 展开 (27)` 后跟 `Aa 翻译标签` 按钮

视觉对齐 OK,点击响应。**实际翻译请求要 DeepL API key**,本次自测没填(留给真机)。

### ✅ #2 进度条缓冲条

Rick Astley `dQw4w9WgXcQ` 视频起播成功(mac IP 这条 yt_explode 路径 OK)。

进度条 zoom 后视觉:
- **0 至 thumb**:实白(已播放)
- **thumb 至中段**:半透白(已缓冲,demuxer-cache-time)
- **中段至右端**:暗灰(未缓冲)
- thumb 圆点清晰

3 层叠加 spec 完全达成。媒体控制层显示 `00:35 / 03:33  360p  1.0x`,起播 + 缓冲指示器全正常。

## 自测设置

- macOS Tahoe 26.4.1 / Darwin 25.4.0 / Apple Silicon
- PiliPlus mac Debug build,Phase A 改动 build 时间 5/19 15:29(App.framework)
- 视频:`dQw4w9WgXcQ` (Rick Astley - Never Gonna Give You Up 4K Remaster)
- 节点:当前 mac 出口(One Last Kiss 仍 LOGIN_REQUIRED,但 Rick Astley/普通视频 OK)

## 剩下要真机验的

- **#6 实际 DeepL 翻译调用**:填 API key 后点"翻译"按钮 → 应原文变译文 + 下方"显示原文"切换。Mac 没填 key
- **#4 导入新格式回环**:粘贴自家导出的 JSON 回来 → 应 B 站 + YT 都 import 不报错
- **真机的反爬环境差异**:你手机 IP 可能某些视频能播某些不能,跟 mac 一样情况

## 交付

`~/Desktop/PiliPlus-phaseA-2026-05-19.ipa`(昨晚 00:31 build,代码就是当前自测过的版本)。

## 工作纪律新增

- 这次先写 reference 拿到 dock fix → 应用 → 自测 → 写 session log,严格遵守 [feedback_check_recency_first.md](../../../../.claude/projects/-Users-adams/memory/feedback_check_recency_first.md) 和 user 多次强调的"测试完了再交付"
- mac GUI 自测打通后,下一轮做 Phase B(#1/#3/#7)时也按此流程
