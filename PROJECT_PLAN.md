# Android Root WebView Demo 项目开发规划文档

## 1. 项目概述
本项目为 Android 单机 APP，核心能力为：通过本地内嵌 WebView 加载网页，并由网页通过指定 JavaScript 函数调用 APP 底层能力；APP 使用 ROOT 权限执行 Shell 命令，并将执行结果以数组形式返回：`[标准输出, 标准错误, 状态码]`。

默认 Demo 命令：`whoami`，用于验证 ROOT 身份。

目标兼容：Android 8.1（API 27）及 32 位设备（`armeabi-v7a`）。

---

## 2. 本期开发目标
1. 实现兼容 Android 8.1+、32 位架构的 WebView 容器
2. 启用 WebView JavaScript，加载本地 `assets/index.html`
3. 实现 JS 函数 `root_cmd(mycmd)` 与 Android 原生桥接
4. APP 以 ROOT 权限执行 Shell 命令并返回结果数组
5. Demo 验证：网页调用 `root_cmd("whoami")` 返回 root
6. 本期不做额外安全、封装、界面优化

---

## 3. 项目范围
### 本期范围
- Android 工程搭建（`minSdkVersion = 27`）
- 32 位 ABI 兼容配置（`armeabi-v7a`）
- WebView 初始化 + JS 启用 + 本地网页加载
- JS <-> 原生桥接，暴露 `root_cmd`
- ROOT Shell 执行逻辑（`su -c`）
- 捕获并返回 `stdout/stderr/exitCode`
- `whoami` 命令 Demo 验证

### 非本期范围
- 命令白名单/过滤
- 超时、异常标准化封装
- 界面美化、多语言、主题
- 服务端、网络、数据库
- 后台保活、多进程
- 64 位单独优化

### 后续迭代方向
- 命令日志
- 超时控制
- 批量/脚本执行
- 结果格式化展示

---

## 4. 功能需求
1. **本地网页加载**：WebView 加载 `assets/index.html`。
2. **JS 桥接**：提供全局函数 `root_cmd(mycmd)`。
3. **ROOT 命令执行**：使用 `su -c` 执行 shell。
4. **结果返回**：返回 `[stdout, stderr, statusCode]`。
5. **Demo 验证**：页面支持手动输入命令执行（默认可用 `whoami` 验证）并展示结果。

---

## 5. 核心流程
APP 启动
→ WebView 加载本地网页
→ 用户输入命令并触发执行
→ JS 调用 `root_cmd(userInputCmd)`
→ 原生接收命令
→ ROOT 执行 shell
→ 收集输出
→ 返回数组
→ 网页展示结果。

---

## 6. 模块拆分
1. **AppCore**：入口 Activity、基础配置、ABI 配置。
2. **WebViewContainer**：WebView 初始化、JS 启用、本地网页加载。
3. **JsBridge**：JS 接口注册、`root_cmd` 映射、结果回传。
4. **RootShellExecutor**：ROOT 执行、流读取、结果组装。

---

## 7. 模块依赖
线性依赖：`AppCore -> WebViewContainer -> JsBridge -> RootShellExecutor`

---

## 8. 技术约束
- 平台：Android APP
- 最低版本：Android 8.1（API 27）
- ABI：`armeabi-v7a`（32 位）
- 开发语言：Java
- 网页资源：本地 `assets/index.html`
- 无第三方 SDK、无服务端、无数据库

---

## 9. 非功能需求
- 兼容性：32 位设备可运行
- 性能：同步执行命令即可
- 安全性：不增加限制，依赖 ROOT 授权
- 稳定性：保证核心调用链路可用

---

## 10. MVP（最小可用版本）
- 全屏 WebView
- `root_cmd` 桥接
- ROOT 命令执行
- `whoami` Demo
- 32 位兼容打包

---

## 11. 开发优先级
- **P0**：工程创建、API27 配置、32 位 ABI、WebView、JS 桥接、ROOT 执行、`whoami` Demo
- **P1**：稳定性增强（命令超时、异步执行、Root 预检查、统一错误码）
- **P2**：体验优化（命令输入增强、命令日志、结果格式化）

---

## 12. 分阶段开发计划
### 阶段 1：工程与基础配置
- 配置 `minSdk=27`
- 配置 `ndk.abiFilters = ["armeabi-v7a"]`
- 建立 Activity + 全屏 WebView
- 启用 JavaScript，加载本地网页

产出：可显示本地网页的 32 位兼容 APP

### 阶段 2：JS 桥接实现
- 编写 `JsInterface`，实现 `root_cmd`
- 网页可调用并传递命令

产出：JS -> 原生通信打通

### 阶段 3：ROOT 命令执行
- 实现 `su -c` 执行 shell
- 读取 `stdout/stderr/exitCode`

产出：可 ROOT 执行任意命令

### 阶段 4：Demo 联调与打包
- 网页内置 `whoami` 调用
- 数组返回并页面展示
- 打包 32 位 APK 测试

产出：完整可交付 Demo

---

## 13. 里程碑
1. 工程 + 32 位配置 + WebView 加载完成
2. JS 调用原生方法成功
3. ROOT 命令执行验证通过
4. `whoami` Demo 联调成功，32 位 APK 可运行

---

## 14. 风险与阻塞
1. 设备未 ROOT 或授权拒绝
2. 部分系统对 `su` 权限限制
3. 32 位设备 WebView 版本过低导致 JS 异常
4. 命令输出乱码（本期不处理）
5. 高危命令可能破坏系统

---

## 15. 确认事项
1. 开发语言：Java
2. 本地网页文件名：`index.html`
3. 提供简单页面样式展示结果

---

## 16. 下一步执行建议
1. 新建 Android 项目并配置 `minSdk=27`、`armeabi-v7a`
2. 实现 WebView 加载本地网页
3. 实现 JS 桥接与 ROOT 执行
4. 加入 `whoami` Demo 并打包 32 位 APK 测试
5. 配置 GitHub Actions：每次 PR 自动编译
