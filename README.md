# RootWebViewDemo

Android 8.1+（API 27）单机 WebView Demo：

- WebView 加载 `assets/index.html`
- JS 暴露全局函数 `root_cmd(mycmd)`
- 原生使用 `su -c` 执行命令
- 返回数组：`[stdout, stderr, statusCode]`
- 支持手动输入命令执行（默认命令 `whoami`）

## 关键文件
- `app/src/main/java/com/example/rootwebviewdemo/MainActivity.java`
- `app/src/main/java/com/example/rootwebviewdemo/JsBridge.java`
- `app/src/main/java/com/example/rootwebviewdemo/RootShellExecutor.java`
- `app/src/main/assets/index.html`
- `.github/workflows/android-pr-build.yml`

## 构建命令
```bash
gradle :app:assembleRelease
```

## 产物位置
本地构建成功后：

```text
app/build/outputs/apk/release/app-release-unsigned.apk
```

GitHub Actions（PR）构建成功后：
- 在 Actions 该次运行页面最底部 **Artifacts** 下载
- 工件名：`app-release-apk`

## CI 自动签名（GitHub Actions）
工作流已支持：
- `push` 到 `main` 自动编译
- `pull_request` 自动编译
- 当签名密钥 secrets 完整配置时，自动产出已签名 `release` APK

需要在 GitHub 仓库 Secrets 中配置：
- `ANDROID_SIGNING_KEYSTORE_BASE64`：keystore 文件的 base64 内容
- `ANDROID_SIGNING_STORE_PASSWORD`
- `ANDROID_SIGNING_KEY_ALIAS`
- `ANDROID_SIGNING_KEY_PASSWORD`

若未配置上述 secrets，CI 仍会编译，但产物为未签名 release APK。

## Android Studio 说明
- 点击 **Run** 是“安装到设备/模拟器并启动”，不是“弹出 APK 文件”。
- 需要 APK 文件时，请用：
  - `Build > Build Bundle(s) / APK(s) > Build APK(s)`
  - 完成后点击提示里的 `locate`

## 页面交互
- 输入命令后按 `Enter` 执行
- `Shift + Enter` 可换行
- 输入框右侧提供“执行”按钮

> 说明：命令执行依赖设备 ROOT 授权；未 ROOT 设备会返回错误信息与非 0 状态码。
