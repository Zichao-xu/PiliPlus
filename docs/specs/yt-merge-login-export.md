# 关于页"导入/导出登录信息"合并 YT

## 现状

- B 站登录在 `Accounts.account` (Hive Box `account`),`toMap()` / `fromJson()` 走 LoginAccount adapter
- YT 登录在 `GStorage.localCache` 4 个 key:`yt_auth_cookies`(JSON 字符串)、`yt_auth_user_name`、`yt_auth_avatar_url`、`yt_auth_channel_id`
- 关于页 [view.dart:319](../../lib/pages/about/view.dart) ListTile "导入/导出登录信息" 当前只处理 B 站

## 目标

同一按钮、同一 JSON 文件 同时管 B 站 + YT。

### 新 JSON schema(导出)

```json
{
  "bilibili": { "<mid>": { "cookies": ..., "accessKey": ... }, ... },
  "youtube": {
    "yt_auth_cookies": "<jsonString>",
    "yt_auth_user_name": "...",
    "yt_auth_avatar_url": "...",
    "yt_auth_channel_id": "..."
  }
}
```

### 导入兼容

- 检测顶层 `"bilibili"` / `"youtube"` key → 新格式,分别 import 两个 section
- 否则 → 旧格式(B 站 mid → LoginAccount map),走原 B 站 import 逻辑
- YT section 全是 nullable,缺哪个跳哪个

## 改动

1. `lib/pages/about/view.dart` ListTile "导入/导出登录信息":
   - `onExport`:返回新 schema(包 bilibili + youtube)
   - `onImport`:检测格式,新格式分别 import,旧格式 fallback 当前逻辑

2. 不动 `YtAuthService.saveCookies` 等 API,只走 `localCache.put`

## 不做

- 不改 "导入/导出设置"(那个走 setting / video box,跟 login 无关)
- 不加密 JSON(B 站本来就明文)

## 验收

1. **导出**:点 "导入/导出登录信息" → 导出 → 得 JSON 含 `bilibili` + `youtube` 两段
2. **导入新格式**:粘贴新 JSON 进来 → B 站登录恢复 + YT "我的"卡片显示"已登录"
3. **导入旧 B 站格式**:粘贴旧 B 站 JSON → B 站登录恢复(YT 不动)
4. **任意 section 缺**:JSON 只有 bilibili 没 youtube,正常 import bilibili 不报错;反之亦然
