# Spec: M3 诊断 — Release ErrorWidget 改红屏显式

> 状态: **派活中**
> 上级: `docs/specs/m3-yt-video-detail.md`
> 失败现象: 真机点 YT 卡片进详情页,**全屏灰色**。Release build 的 default ErrorWidget 是无信息灰色容器,无法定位异常。
> 执行: workbuddy (`kimi-k2.6 + high`)

## 目标

把 Flutter release build 的默认 ErrorWidget 替换为**可读红屏显式输出 exception + stack**,以便用户截图把异常贴回来,我快速定位 root cause。

**这是诊断步骤**,验证 M3 root cause 后会还原。

## 边界

- ✅ 只改 `lib/main.dart`(找到 main 函数,在 `runApp(...)` 之前注入 builder)
- ❌ 不动其他任何文件
- ❌ 不"顺手"加其他 debug 工具

## 改动

`lib/main.dart` 顶部 import 已有 material,在 `main()` 函数体内、**`runApp(...)` 调用之前**插入:

```dart
ErrorWidget.builder = (FlutterErrorDetails details) {
  return Material(
    color: const Color(0xFFB00020),
    child: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          'EXCEPTION:\n${details.exception}\n\n'
          'LIBRARY:\n${details.library ?? "-"}\n\n'
          'CONTEXT:\n${details.context ?? "-"}\n\n'
          'STACK:\n${details.stack}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontFamily: 'monospace',
          ),
        ),
      ),
    ),
  );
};
```

**如果 main.dart 已有 main() 之外的初始化结构**(如 `void main() async { WidgetsFlutterBinding.ensureInitialized(); ... }`),把这块 ErrorWidget.builder = ... 放在 `WidgetsFlutterBinding.ensureInitialized()` 之后、`runApp` 之前最合适。

**先 Read** `lib/main.dart` 全文(不长),决定准确插入位置。

## 自验

```bash
cd /Users/adams/PiliPlus
~/development/flutter/bin/flutter analyze lib/main.dart
```
要求 0 issue。

## 输出格式

100 字内中文摘要 + analyze 输出。

## 不做什么

- ❌ 不动 main.dart 现有逻辑
- ❌ 不动其他 dart 文件
- ❌ 不删 / 不动 docs/、scratch/
- ❌ 不 commit git
