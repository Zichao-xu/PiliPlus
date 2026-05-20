# AGENTS.md

> PiliPlus 项目协作约定。所有 AI 代理(Claude Code / workbuddy / 其他)开工前先读这份。

## 项目身份

PiliPlus 是 Bilibili 第三方 Flutter 客户端。本仓库在上游基础上扩展多源(YouTube 等)能力,核心目标是 **iOS via TrollStore** 自用。

- **平台**: Flutter,主目标 iOS;Android / macOS / Linux / Windows 上游已有,我们不主动维护
- **iOS 构建**: `--no-codesign`,TrollStore 安装,无需签名
- **Dart SDK / Flutter**: 见 `.fvmrc` 与 `pubspec.yaml`

## 谁出什么

- **决策与验收**: 用户
- **技术方案 / spec / 代码**: AI 商讨并起草
- **执行落地**: 优先派 workbuddy 干批量 / 扫读 / 改动明确的活;军师不下场——哪怕 1 行也写 spec

## 文档结构

```
docs/
  sessions/   # 每次重要对话一份,文件名 YYYY-MM-DD-<topic>.md
  specs/      # 实施 spec,改动前必须先有
```

- **不写 CLAUDE.md**(项目级也不写)
- README 保持上游原貌,本仓库独有信息进 `docs/`

## 起手式

新会话进来,按需读:

1. `AGENTS.md`(这份)
2. `docs/sessions/` 最新两三份,理解当前在做什么
3. 当前任务对应的 `docs/specs/<name>.md`

## 改动纪律

- **改动前先有 spec**: 修一行也写,spec 落在 `docs/specs/`
- **session log 在事后写**: 决策定了 / 任务做完 / 方向转向 时写一份
- **派活先有 spec**: workbuddy 接到的活必须指向某个 spec,不口头派
- **上游同步**: 上游频繁更新,本仓库改动尽量集中在新文件 / 隔离目录,少改上游文件,降低 rebase 成本

## 沟通约定(对 AI)

- **结论先讲**: 长篇大论之前先给一句话结论
- **中文**: 默认中文回复
- **大决策给选项**: 不替用户拍板,列选项 + 推荐 + 理由
- **不要无关 preamble**: 不说 "好的我来帮你..." 直接干

## 当前活跃工作

- **multi-source-mvp**: 接入 YouTube 作为第二个视频源,只做搜索混排 + 播放 + 简介 + 评论。spec: `docs/specs/multi-source-mvp.md`
