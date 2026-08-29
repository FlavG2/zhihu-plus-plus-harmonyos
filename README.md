# 知乎++（鸿蒙版）Zhihu++ HarmonyOS NEXT

> 第三方知乎客户端 · 安卓 [zly2006/zhihu-plus-plus](https://github.com/zly2006/zhihu-plus-plus) 的 HarmonyOS NEXT 移植版

## 简介

本项目由 FlavG2 指挥 WorkBuddy、CodeX 等工具进行移植，代码全部由AI工具完成，本人不会写代码，也不参与写代码。

## 功能特性

### 信息流

- **主页推荐** — 知乎首页信息流，支持下拉刷新与无限滚动加载
- **关注** — 关注推荐流 + 动态流双 Tab 切换
- **热榜** — 知乎热榜实时排行，游客可访问
- **日报** — 知乎日报按日期分组，支持封面图与更早日期加载

### 账号与登录

- 账号密码登录
- 二维码扫码登录
- 身份管理（主账号 + 马甲号创建 / 切换）
- 会话持久化（Cookie + 移动端令牌），`sessionEpoch` 触发整页重载

### 内容浏览

- 文章 / 回答 / 想法详情页（富文本渲染）
- 视频播放页
- 个人主页（关注订阅、动态列表）
- 评论系统（文章 / 回答 / 想法统一评论 + 楼中楼回复）

### 搜索与发现

- 搜索页（热搜展示 / 搜索输入 / 结果分页）
- 搜索历史持久化（最多 20 条去重置顶）
- 剪贴板快捷搜索（用户主动触发）

### 收藏与历史

- 收藏 / 取消收藏 / 新建收藏夹
- 我的收藏夹列表（含创建入口）
- 浏览历史（本地 + 云端），清空操作含二次确认弹窗

### 通知

- 通知中心
- 通知设置

### 内容过滤

- 推荐过滤（关键词 / 用户 / 话题）
- 屏蔽名单管理
- 屏蔽历史记录
- 质量过滤设置
- 智能过滤设置

### 外观与阅读

- 日间 / 黑暗 / 跟随系统主题切换
- 沉浸光感（材质等级调节）
- OLED 纯黑模式
- 缩略图开关
- 刷新 FAB 开关

### 深链唤起

- 支持从系统浏览器打开 `zhihu.com` 各子域链接
- 支持 `zhihu://` scheme 直接跳转对应内容页
- `EntryAbility` 捕获 `want.uri` → AppStorage `pendingDeepLink` → 首页消费导航

## 技术栈

| 项目 | 说明 |
| --- | --- |
| 语言 | ArkTS（TypeScript 扩展） |
| UI 框架 | ArkUI（声明式） |
| 目标平台 | HarmonyOS NEXT |
| targetSdkVersion | 6.1.1(24) |
| compatibleSdkVersion | 6.1.0(23) |
| 设备类型 | phone / tablet |
| 运行期依赖 | **零三方库**，仅使用系统 Kit |
| 开发依赖 | @ohos/hamock 1.0.0（测试 Mock）、@ohos/hypium 1.0.25（测试框架） |

### 系统 Kit 清单

ArkUI · ArkWeb · AbilityKit · ArkData · NetworkKit · CoreFileKit · ShareKit · BasicServicesKit · PerformanceAnalysisKit · UIDesignKit

> 随 HarmonyOS 操作系统分发，非应用再分发。

## 工程结构

```text
zhihu-plus-plus-harmonyos/
├── AppScope/
│   └── app.json5                    # 应用级配置（包名、版本）
├── entry/
│   ├── src/main/
│   │   ├── ets/
│   │   │   ├── entryability/        # EntryAbility（启动、深链入口）
│   │   │   ├── entrybackupability/  # 备份恢复
│   │   │   ├── models/              # 数据模型（ZhihuModels, ZhihuContentModels）
│   │   │   ├── pages/               # 24 个页面（见下方清单）
│   │   │   ├── services/            # 业务逻辑层（API、Feed、评论、收藏…）
│   │   │   ├── components/          # 复用组件（ZhihuRichWeb）
│   │   │   ├── utils/               # 工具（时间格式化、HTML 解析、蛇形转换）
│   │   │   └── generated/           # 构建时注入（BuildInfo.ts: 版本号/Git Hash）
│   │   ├── module.json5             # 模块配置（权限、页面路由、深链 skill）
│   │   └── resources/               # 资源（颜色、字符串、图标、多语言）
│   └── oh-package.json5             # 依赖声明
├── oh_modules/                      # OhPM 缓存（hamock, hypium）
├── build-profile.json5              # 构建配置（SDK 版本、签名）
├── oh-package.json5                 # 工程依赖
├── hvigor/                          # 构建脚本配置
└── LICENSE                          # AGPL-3.0 完整许可证文本
```

### 已注册页面（main_pages.json）

Index · Login · QrLogin · Search · WebContent · Article · Question · Pin · CollectionList · CollectionDetail · VideoPlayerPage · People · Notification · NotificationSettings · FilterSettings · AppearanceSettings · BlocklistManage · BlockHistory · QualityFilterSettings · SmartFilterSettings · History · IdentityManagement · About · Licenses

## 架构要点

- **网络层**：`ZhihuApi.ts` 统一封装 HTTP 请求，自动携带 Cookie 与鉴权头
- **会话管理**：`ZhihuSessionRepository` 持久化 Cookie / 移动端令牌；`sessionEpoch` 计数器驱动首页整页重载（对齐安卓 recreate + CLEAR_TASK）
- **主题系统**：`ThemeColors` 统一 OLED 黑 / 黑暗 / 日间三套着色方案
- **深链分发**：`ZhihuNavigation.openZhihuContentTarget()` 根据 URL 类型路由到 Article / Question / Pin / People 等目标页
- **身份管理**：`ZhihuIdentityClient` 封装马甲号 list / create / switch；`IdentityManagement.ets` 提供创建 / 切换 UI

## 构建

### 前提条件

- DevEco Studio（含 SDK、hvigor、Node.js 运行时）
- Java 21（jbr）

### 预编译准备：generated/BuildInfo.ts

`entry/src/main/ets/generated/BuildInfo.ts` 提供 `APP_VERSION_NAME`（需与 `AppScope/app.json5` 的 `versionName` 保持一致）与 `GIT_COMMIT`（用于「系统与更新」页版本展示）。

- **默认情况**：本仓库已预置该文件。因本地并非 git 仓库，`GIT_COMMIT` 回退至上游基线 `86db2b6`，首次克隆后**无需额外操作**即可编译。
- **若启用 git 提交哈希注入**：请确保本地为 git 仓库，并在构建前生成 / 同步该文件（例如通过 git hook 或 hvigor 构建任务注入真实 `GIT_COMMIT`），否则会因 `APP_VERSION_NAME` / `GIT_COMMIT` 导入失败导致编译报错。
- **环境变量兜底（可选）**：若构建链路支持，可通过环境变量 `APP_VERSION_NAME` / `GIT_COMMIT` 覆盖文件内默认值，避免硬编码。

### 未签名 HAP 构建（CLI）

```powershell
$env:PATH = "D:\DevEco Studio\jbr\bin;" + $env:PATH
$env:DEVECO_SDK_HOME = "D:\DevEco Studio\sdk"
Remove-Item Env:NODE_OPTIONS -ErrorAction SilentlyContinue
Set-Location "zhihu-plus-plus-harmonyos"
& node "D:\DevEco Studio\tools\hvigor\bin\hvigorw.js" assembleHap --mode module -p product=default --no-daemon
```

产物：`entry/build/default/outputs/default/entry-default-unsigned.hap`

> 注：当前 product 未配置签名配置（`signingConfigs` 为空）。真机安装需在 DevEco Studio 中配置签名后重新构建。

## 开源与许可

Copyright (C) 2024 zly2006 — 安卓原项目 [zhihu-plus-plus](https://github.com/zly2006/zhihu-plus-plus)
Copyright (C) 2026 xlwreally — 鸿蒙基底项目 [zhihu-plus-plus-next](https://github.com/xlwreally/zhihu-plus-plus-next)（HarmonyOS NEXT 适配）
Copyright (C) 2026 FlavG2 — 知乎++（鸿蒙版）移植与维护

本应用基于 **AGPL-3.0-only** 协议发布，完整许可证文本见根目录 [LICENSE](./LICENSE)。

上游致谢：

- 安卓原项目：[zly2006/zhihu-plus-plus](https://github.com/zly2006/zhihu-plus-plus)
- 鸿蒙基底项目：[xlwreally/zhihu-plus-plus-next](https://github.com/xlwreally/zhihu-plus-plus-next)（Commit 86db2b6）

系统 Kit 随 HarmonyOS 操作系统分发，非应用再分发。
### 免责声明（Warranty Disclaimer）

本程序按「原样」提供，**不提供任何明示或暗示的担保**，包括但不限于对适销性和特定用途适用性的暗示担保。全部使用风险由您承担。若程序被证明存在缺陷，您须自行承担所有必要的维护、修理或更正费用。

在任何情况下，任何版权持有人或其他参与者均不对因使用或无法使用本程序而造成的任何损害（包括但不限于数据丢失、数据不准确、或任何第三方损失）承担责任，即使已被告知该等损害的可能性。

完整法律文本以根目录 [LICENSE](./LICENSE) 第 15 条（免责担保）与第 16 条（责任限制）为准。

## 声明

本软件仅供学习交流使用，应用内内容由知乎网站提供，著作权归其对应作者所有。本项目与知乎官方无关联。
