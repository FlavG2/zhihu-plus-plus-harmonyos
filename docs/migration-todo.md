# HarmonyOS NEXT 迁移待办清单

本文档基于当前 HarmonyOS NEXT 工程源码和 Android 原项目子模块整理，用于跟踪 `zhihu-plus-plus-next` 还有哪些能力没有迁移。

## 当前已迁能力

- 应用壳：Stage Model + ArkTS + 单 `entry` HAP。
- 页面注册：当前仅注册 `Index`、`Login`、`WebContent`、`Article`。
- 主页推荐流：已接入 `topstory/recommend`，支持登录态、首屏加载、翻页、错误重试。
- 关注页：已接入关注推荐流和关注动态流，支持子页切换、首屏加载、翻页、错误重试。
- 知乎日报：已接入最新日报和历史日报接口，支持封面图、日期分组、加载更多、点击进入详情或 Web fallback。
- 历史页：已接入 Harmony 侧本地最近浏览，支持列表回跳和清空。
- 登录：已提供知乎网页登录入口，可从 WebView Cookie 校验登录并保存会话。
- 基础账号面板：支持显示账号信息、打开我的主页 Web 页、刷新主页、退出登录。
- 内容详情：已支持回答、文章、问题、想法 Pin 的基础详情展示。
- 评论：已支持根评论、子评论、评论回复、评论点赞、排序和加载更多。
- 富文本展示：已使用 Web 富文本容器展示知乎内容，并处理主题、正文链接和图片点击。
- 基础主题：已支持日间、黑暗、跟随系统三种主题模式。
- 签名请求：已迁移基础 `x-zse-96` 签名生成和 Cookie 请求封装。
- 表情：已迁移知乎表情文本/HTML 替换与缓存能力。

## README 状态校正

根目录 `README.md` 中部分“当前限制”已经过时：

- “主页 / 关注 / 历史仍是占位入口”已不准确：当前已存在主页推荐流、关注推荐/动态流和本地最近浏览历史。
- “日报列表暂未接入详情页跳转”已不准确：日报卡片已可跳转原生详情或 Web fallback。
- “日报卡片暂未接入封面图”已不准确：当前 `DailyService` 已解析 `images[0]`，卡片也会显示封面。

建议后续同步更新 README，避免迁移状态与源码不一致。

## 未迁移清单

### 1. 一级入口与导航

- [x] 关注页：已迁移关注推荐流和关注动态流。
- [x] 历史页：已迁移 Harmony 侧本地最近浏览历史。
- [x] 热榜页：Harmony 侧已注册 `热榜` 一级入口。
- [ ] 在线历史页：Android 原项目有 `OnlineHistory` 顶级入口，Harmony 侧尚未注册。
- [ ] 完整账号设置页：Harmony 当前只有底部弹出的账号面板，没有 Android 原项目的完整 `AccountSettingScreen`。
- [ ] 顶级导航结构：Android 原项目包含 `Home / Follow / HotList / Daily / OnlineHistory / Account`，Harmony 侧当前已有 `主页 / 关注 / 热榜 / 日报 / 历史`，仍缺在线历史和完整账号入口。

### 2. 信息流与推荐

- [x] 关注页推荐流。
- [x] 关注页动态流。
- [ ] 最近关注用户动态。
- [x] 热榜信息流。
- [ ] 在线历史信息流。
- [x] Harmony 侧本地最近浏览历史记录。
- [ ] 首页推荐模式切换：Web / 安卓 / 本地 / 混合。
- [ ] 登录状态 / 非登录状态推荐切换。
- [ ] 本地推荐算法。
- [ ] 本地内容爬取、缓存、调度。
- [ ] 本地推荐数据库和行为分析。

### 3. 搜索

- [x] 原生搜索页。
- [x] 热搜展示。
- [x] 搜索结果分页。
- [x] 搜索结果卡片复用。

当前 Harmony 侧首页搜索入口已进入原生搜索页，支持热搜、搜索结果分页与内容详情跳转。

### 4. 内容浏览

- [ ] 问题详情完整页：回答列表、排序、关注问题、日志、分享、评论入口等。
- [ ] 回答切换：上下/左右切换手势。
- [ ] 下一个回答按钮。
- [ ] 回答预加载和缓存导航。
- [ ] 独立想法 Pin 详情页：点赞、话题、分享等完整交互。
- [ ] 视频内容页。
- [ ] 个人主页原生页。
- [ ] 用户回答、文章、动态、关注、粉丝、收藏、提问、想法、专栏贡献等分页。
- [ ] 收藏夹列表。
- [ ] 收藏夹内容列表。
- [ ] 内容收藏/取消收藏。
- [ ] 创建收藏夹。
- [ ] 分享弹窗。
- [ ] 长按保存图片。
- [ ] 无水印保存图片。
- [ ] 内容导出：PDF、图片、Markdown。
- [ ] AI 总结内容。
- [ ] TTS 朗读回答/文章。

### 5. 社区互动

- [ ] 关注用户。
- [ ] 拉黑用户。
- [ ] 屏蔽推荐。
- [ ] 按关键词屏蔽内容。
- [ ] 从内容页快速加入屏蔽词。
- [ ] 从评论/作者入口进入用户操作面板。
- [ ] 通知页。
- [ ] 通知筛选。
- [ ] 全部标记已读。
- [ ] 通知设置。

当前 Harmony 侧已迁移评论读取、回复和点赞，但社区互动的其他能力还未迁移。

### 6. 屏蔽与过滤系统

- [ ] 屏蔽词管理。
- [ ] 正则屏蔽词。
- [ ] NLP 屏蔽词。
- [ ] 屏蔽用户。
- [ ] 屏蔽话题。
- [ ] 反向屏蔽。
- [ ] 质量过滤。
- [ ] 智能内容过滤。
- [ ] 过滤统计。
- [ ] 屏蔽记录。
- [ ] 被屏蔽内容历史。
- [ ] 屏蔽规则导入。
- [ ] 屏蔽规则导出。
- [ ] 过滤数据库迁移与清理。

当前账号面板里“推荐系统与内容过滤”仍是待迁移入口。

### 7. AI / NLP / Full 版本能力

- [ ] ONNX / embedding 推理依赖。
- [ ] Sentence embedding 管理。
- [ ] 关键词向量相似度匹配。
- [ ] NLP 关键词管理页。
- [ ] 相似度测试页。
- [ ] Full / Lite 差异化能力。

当前 Harmony `entry` 依赖为空，尚未引入相关推理或数据库能力。

### 8. 登录与账号

- [ ] 手机验证码登录。
- [ ] 电脑端扫码登录。
- [ ] 手动 Cookie 登录。
- [ ] 登录状态切换策略。
- [ ] 账号设置完整页面。
- [ ] Cookie 管理与调试入口。
- [ ] 账号信息刷新策略。

当前仅支持 WebView 登录后从 Cookie 校验。

### 9. 设置页

- [ ] 外观设置完整项。
- [ ] 阅读体验设置完整项。
- [ ] 推荐与过滤设置页。
- [ ] 屏蔽列表设置页。
- [ ] 系统与更新设置页。
- [ ] 开发者设置页。
- [ ] 配色方案页。
- [ ] 设置项高亮跳转。
- [ ] 设置持久化模型补齐。

当前仅迁移了主题模式切换。

### 10. Deep Link、剪贴板与二维码

- [ ] Harmony Ability skills 中注册知乎 URL / `zhihu://` scheme 入口。
- [ ] 从外部链接进入对应原生内容页。
- [ ] 启动时读取剪贴板知乎链接并提示跳转。
- [ ] 二维码扫描页。
- [ ] 二维码扫描结果展示和复制。

当前只有内部 `resolveZhihuContent()` 可解析部分知乎链接，但没有外部入口和剪贴板流程。

### 11. 系统能力与工程能力

- [ ] 本地数据库层。
- [ ] 备份/恢复真实数据项。
- [ ] 文件保存与分享权限适配。
- [ ] 通知权限与通知能力。
- [ ] TTS 系统能力适配。
- [ ] Harmony 侧单元测试。
- [ ] Harmony 侧页面/集成测试。
- [ ] 构建告警清理。
- [ ] README 与实际迁移状态同步。

当前 `EntryBackupAbility` 已存在，但尚未看到真实备份/恢复数据配置。

## 建议迁移优先级

### P0：补齐主流程

1. 在线历史页。
2. 完整账号设置页。
3. README 状态同步。

### P1：补齐内容闭环

1. 个人主页。
2. 收藏夹和收藏夹内容。
3. 问题详情回答列表。
4. 内容分享。
5. 收藏/取消收藏。
6. 通知页。

### P2：补齐高级能力

1. 推荐模式切换。
2. 本地推荐与本地历史。
3. 屏蔽/过滤系统。
4. 导入导出屏蔽规则。
5. TTS。
6. 内容导出。

### P3：补齐重型能力

1. AI/NLP 过滤。
2. Sentence embedding。
3. AI 总结。
4. Full / Lite 分包策略。
5. 二维码扫描。
6. Deep Link 和剪贴板识别。

## 参考源码位置

- Harmony 页面注册：`entry/src/main/resources/base/profile/main_pages.json`
- Harmony 主页面：`entry/src/main/ets/pages/Index.ets`
- Harmony 登录页：`entry/src/main/ets/pages/Login.ets`
- Harmony 内容详情页：`entry/src/main/ets/pages/Article.ets`
- Harmony 主页推荐服务：`entry/src/main/ets/services/HomeFeedService.ts`
- Harmony 日报服务：`entry/src/main/ets/services/DailyService.ts`
- Harmony 内容详情服务：`entry/src/main/ets/services/ArticleDetailService.ts`
- Harmony 评论服务：`entry/src/main/ets/services/CommentService.ts`
- Harmony 签名服务：`entry/src/main/ets/services/ZhihuSignerBridge.ts`
- Android 原项目路由：`zhihu-plus-plus/app/src/main/java/com/github/zly2006/zhihu/NavDestination.kt`
- Android 原项目主导航：`zhihu-plus-plus/app/src/main/java/com/github/zly2006/zhihu/ui/ZhihuMain.kt`
- Android 原项目功能说明：`zhihu-plus-plus/README.md`
