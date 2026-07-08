# Action Ring

当前版本：`v1.9.14`

一个面向 `macOS` 的自定义悬浮程序坞。

目标很明确：
- 不替代系统 `Dock`
- 不做复杂搜索器，只保留轻量 App 搜索
- 不做复杂模式切换
- 只解决“快速找到并打开固定应用”

核心思路：
- 用全局快捷键呼出面板
- 面板里只放用户自己编排的 App
- 右侧输入框支持快速搜索和打开本机 App
- 以 `上 / 右 / 下 / 左` 四个方向分组
- 每组最多 `3` 个 App，顺序长期固定
- 点击后执行“启动应用”或“切到前台”

当前原型状态：
- `Swift Package` 形式的 `macOS` 原生原型
- 菜单栏常驻入口
- 支持自定义全局快捷键
- 支持按 `上 / 右 / 下 / 左` 四组展示的环形浮层
- 支持应用管理窗口
- 支持按组添加 App、删除 App、组内排序、跨组移动、恢复默认
- 支持扫描本机已安装应用并搜索添加
- 支持唤醒态右侧搜索框，输入英文后按回车打开选中结果
- 支持本地配置持久化
- 支持登录项状态检测与 `Launch at Login` 开关

运行方式：
- `swift build`
- `swift run ActionRing`

打包成 `.app`：
- `./scripts/build-app.sh`
- 打包输出：`dist/Action Ring.app`
- 启动：`open "dist/Action Ring.app"`
- 图标：打包时会自动生成并写入 `AppIcon.icns`
- 安装：运行后可从菜单栏或设置页直接安装到 `~/Applications`
- 说明：`Launch at Login` 只有从真正的 `.app` 包运行时才可用

配置说明：
- 配置文件路径：`~/Library/Application Support/ActionRing/apps.json`
- 管理入口：菜单栏图标 -> `Manage Apps`
- 快捷键修改入口：`Manage Apps` 窗口顶部 `Shortcut` 区域
- 分组结构：`Up / Right / Down / Left`，每组最多 `3` 个 App

文档：
- 方案设计：[docs/design-v1.0.0.md](docs/design-v1.0.0.md)
- UI 规格：[docs/ui-spec-v1.0.1.md](docs/ui-spec-v1.0.1.md)
- 更新记录：[CHANGELOG.md](CHANGELOG.md)
- 版本文件：[VERSION](VERSION)
