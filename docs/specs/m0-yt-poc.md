# Spec: M0 — YouTube 独立最小 POC

> 状态: **派活中**
> 上级 spec: `docs/specs/multi-source-mvp.md` § M0
> 执行: workbuddy (`kimi-k2.6 + effort xhigh`)
> 主工程零改动

## 目标

在 `~/PiliPlus/scratch/yt_poc/` 建立独立 dart 命令行工程,依赖 `youtube_explode_dart`,跑通三件事:

1. **搜索**: 关键词 → 视频列表
2. **取流**: videoId → 直链 URL,本机能播
3. **取评论**: videoId → 评论首屏 + 翻页

跑通后写一份 session log 归档。

## 边界

- ✅ **可做**: 创建 `scratch/yt_poc/` 工程、装依赖、写脚本、跑命令、改 `.gitignore`、写 session log
- ❌ **不可做**: 改 PiliPlus 主工程任何文件(`lib/` / `ios/` / `pubspec.yaml` 等)
- ❌ **不可做**: 安装 mpv / VLC 等系统软件(若本机没有,就在 README 里写"需要 mpv,用户自行装",不要自己装)

## 输入(精确路径)

- 工作目录: `/Users/adams/PiliPlus`
- POC 工程根: `/Users/adams/PiliPlus/scratch/yt_poc/`
- 主工程 dart sdk 版本参考: `/Users/adams/PiliPlus/.fvmrc` 与 `/Users/adams/PiliPlus/pubspec.yaml`(只读,做版本对齐参考)

## 做什么(详细步骤)

### 1. 工程初始化

```bash
cd /Users/adams/PiliPlus
mkdir -p scratch/yt_poc
cd scratch/yt_poc
dart create -t console-simple .   # 或等效手写 pubspec.yaml + bin/
```

`scratch/yt_poc/pubspec.yaml` 最小化:
- name: yt_poc
- environment.sdk: 与主工程 `.fvmrc` 对齐的 dart sdk 区间
- dependencies: `youtube_explode_dart: ^2.x`(取 pub.dev 上的最新稳定 2.x 版本,记在 README)

### 2. `.gitignore`

在 `/Users/adams/PiliPlus/.gitignore` **追加**(不覆盖原内容)一行:
```
scratch/
```
理由: POC 不入主仓库;成品参考靠 README 和 session log 留痕。

### 3. 三个脚本

#### `bin/search.dart`
- 输入: 命令行参数 `<keyword>`,默认 `flutter tutorial`
- 行为: 用 `YoutubeExplode().search.search(keyword)` 拉第一页
- 输出(stdout): 每条一行,格式 `[idx] <videoId> | <duration> | <author> | <title>`,共 10-20 条

#### `bin/stream.dart`
- 输入: 命令行参数 `<videoId>`,默认 `dQw4w9WgXcQ`(或换一个不会被风控的常驻视频)
- 行为: `YoutubeExplode().videos.streamsClient.getManifest(videoId)`
- 输出(stdout):
  ```
  Title: <title>
  Author: <author>
  Duration: <duration>
  --- Muxed streams ---
  <itag> <quality> <container> <bitrate> <url>
  ...
  --- Audio-only ---
  ...
  --- Video-only ---
  ...
  ```
- README 里加一句: 取一条 muxed 的 URL 复制到浏览器 / `mpv <url>` / VLC 验证能播

#### `bin/comments.dart`
- 输入: 命令行参数 `<videoId>`,同上默认
- 行为: 取首屏评论,再用返回的 continuation 取第二页
- 输出(stdout):
  ```
  --- Page 1 (N items) ---
  [1] <author> · <likes> likes · <time>
      <text 截断 80 字>
  ...
  --- Page 2 (N items) ---
  ...
  ```
- 若 youtube_explode_dart 当前版本评论 API 名字不同,以实际为准,**在 README 里记下用的哪个 API**

### 4. README

`scratch/yt_poc/README.md`,包含:
- 用途(指回上级 spec)
- 选用 youtube_explode_dart 的具体版本号
- 跑法:
  ```
  cd scratch/yt_poc
  dart pub get
  dart run bin/search.dart "lex fridman"
  dart run bin/stream.dart dQw4w9WgXcQ
  dart run bin/comments.dart dQw4w9WgXcQ
  ```
- 三个脚本各自的预期输出片段(粘真实跑出来的)
- 踩到的坑(API 名字、网络要求、字段缺失等)
- 写明: 流 URL 要用 mpv/VLC 实测播过

### 5. 实测跑一遍

**全部三个脚本必须真的跑过一次**:
- `dart pub get` 成功
- `dart run bin/search.dart` 至少看到 5 条结果
- `dart run bin/stream.dart` 看到至少 1 条 muxed 流 URL
- `dart run bin/comments.dart` 看到两页评论
- 把真实输出片段贴进 README

如果机器在中国大陆无法直连 YouTube,**先停下,不要伪造输出**,在报告里说"网络不通,请用户检查 VPN/代理"。

### 6. Session log

写到 `/Users/adams/PiliPlus/docs/sessions/2026-05-15-yt-poc-done.md`:
- 选用版本
- 实际跑出来的样例(每个脚本一段)
- 流是否实测可播(由用户后续验证,这里只写 URL 类型 / 是否有 muxed)
- 踩到的坑
- 给 M1 的注意点: 接进主工程时哪些 API 调用是确认可用的、签名是什么

## 输出格式(交还给我时)

执行完毕后,**一段不超过 200 字的中文摘要**, 含:
1. 三件事各自跑通状态(✅/❌)
2. 选用 youtube_explode_dart 版本
3. 主要坑(若有)
4. 改动文件清单(全部 `scratch/yt_poc/` 内 + 主仓库 `.gitignore` 一行 + `docs/sessions/...`)

## 失败时

任意一件没跑通:
- **不要继续做后面的步骤**
- **不要伪造输出**
- 在报告里写明: 卡在哪一步、错误信息、自己尝试过什么、需要什么(是用户改网络? 换版本? 换 API?)
- 把已完成部分留在 `scratch/yt_poc/`,不删

## 不做什么

- ❌ 不要改 PiliPlus 主工程的 `lib/` / `ios/` / `pubspec.yaml`
- ❌ 不要把 youtube_explode_dart 加进主工程的 pubspec
- ❌ 不要写"通用 source 抽象接口"或"未来 M1 怎么集成"的代码 — 那是 M1 的事
- ❌ 不要装系统软件(mpv/VLC/ffmpeg)
- ❌ 不要提交 git
- ❌ 不要伪造"实测可播"
