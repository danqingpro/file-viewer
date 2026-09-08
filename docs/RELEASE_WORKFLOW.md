# Release Workflow Checklist

每次版本升级必须按以下顺序执行，**缺一不可**。

---

## 1. 修改版本号 & 变更日志

同步更新 4 个文件，版本号 `X.Y.Z+BuildN`：

| 文件 | 位置 | 说明 |
|------|------|------|
| `lib/core/config/app_info.dart` | `version` / `versionNumber` / `buildNumber` | 版本号常量 |
| `lib/core/config/app_info.dart` | `changeLog` 列表顶部 | 新增一条 `VersionChangeLog` |
| `pubspec.yaml` | `version: X.Y.Z+BuildN` | Flutter 版本号 |
| `android/local.properties` | `flutter.versionName` / `flutter.versionCode` | Android 版本号 |
| `version.json` | 整个 JSON | 远程更新检测源（`latestVersion` / `apkUrl` / `changelog`） |

递增规则：修复 bug → `Z+1`；新增功能 → `Y+1, Z=0`；破坏性变更 → `X+1, Y=0, Z=0`。`BuildN` 每次 +1。

---

## 2. 构建 APK

**必须使用 JDK 17**（JDK 25 与 AGP 8.6.0 不兼容）：

```bash
cd /workspace
export JAVA_HOME=/root/.local/share/mise/installs/java/17
export ANDROID_HOME=/root/android-sdk
export PATH=$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH
flutter build apk --release
```

输出路径：`build/app/outputs/flutter-apk/app-release.apk`

复制到 release 目录：

```bash
cp build/app/outputs/flutter-apk/app-release.apk releases/file-viewer-X.Y.Z.apk
```

> 注：`releases/` 已加入 `.gitignore`，不会被 commit。

---

## 3. 提交源码

```bash
cd /workspace
git add -A
git commit -m "feat: 简要描述 (vX.Y.Z)"
```

**禁止在源码中提交真实 GitHub PAT**。`lib/core/config/github_config.dart` 中的 `token` 必须为空字符串 `''`。

---

## 4. 推送到 GitHub

```bash
# 先 pull 再 push，避免冲突
git pull --rebase origin main
git push origin main
```

推送后验证：`curl -s https://raw.githubusercontent.com/danqingpro/file-viewer/main/version.json`

---

## 5. 打 Tag & 创建 Release

```bash
VERSION="X.Y.Z"

# 打 tag 并推送
git tag -a "v$VERSION" -m "v$VERSION: 简要描述"
git push origin "v$VERSION"

# 创建 GitHub Release（--latest 标记为最新）
gh release create "v$VERSION" \
  --title "v$VERSION - 标题" \
  --notes "## 新功能\n- ...\n\n## 修复\n- ..." \
  --latest

# 上传 APK 资产
gh release upload "v$VERSION" "releases/file-viewer-$VERSION.apk"
```

验证：
- Tags 页面：https://github.com/danqingpro/file-viewer/tags
- Releases 页面：https://github.com/danqingpro/file-viewer/releases
- APK 下载链接返回 200：`curl -sI https://github.com/danqingpro/file-viewer/releases/download/vX.Y.Z/file-viewer-X.Y.Z.apk | head -1`

---

## 6. 验证远程更新检测

```bash
echo "=== raw.githubusercontent.com ==="
curl -s https://raw.githubusercontent.com/danqingpro/file-viewer/main/version.json

echo "=== fastly.jsdelivr.net (CDN 延迟 ~24h) ==="
curl -s https://fastly.jsdelivr.net/gh/danqingpro/file-viewer@main/version.json

echo "=== cdn.jsdelivr.net (CDN 延迟 ~48h) ==="
curl -s https://cdn.jsdelivr.net/gh/danqingpro/file-viewer@main/version.json
```

CDN 镜像有缓存延迟，但 app 的更新检测逻辑会**遍历所有镜像取最高版本**，只要 raw 正确即可。

---

## 常见陷阱

| 陷阱 | 后果 | 解决 |
|------|------|------|
| 改了本地 version.json 没 push | app 永远检查不到新版本 | 流程第 4 步 |
| push 了 commit 没打 tag / Release | GitHub Tags 页面看不到新版本 | 流程第 5 步 |
| Release 没有 APK 资产 | app 点更新时下载 404 | 流程第 5 步 `gh release upload` |
| 用 JDK 25 构建 | Gradle 报 `25.0.2` 错 | 强制 `JAVA_HOME=/root/.local/share/mise/installs/java/17` |
| github_config.dart 含真实 PAT | GitHub Push Protection 拦截 push，token 泄露风险 | push 前确保 token 为空字符串 |
| 所有镜像不可达 | 旧版 app 静默误报「已是最新版本」 | v1.10.3 已修复，抛 `UpdateFetchException` |
