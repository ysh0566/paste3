# paste3

paste3 是一个 macOS 剪贴板历史工具，目标是做一个本地优先、开源、面向开发者工作流的轻量 Paste 替代品。它会在菜单栏常驻，记录最近复制的内容，并提供类似底部浮层的横向历史浏览体验。

当前项目仍处于早期阶段，默认把隐私和可审计性放在功能复杂度之前。

## 当前能力

- 监听系统剪贴板变化并保存历史记录。
- 支持文本、链接、命令、图片、文件、富文本、HTML 和通用数据片段。
- 使用 SwiftData 在本机持久化剪贴板历史。
- 按内容 hash 去重，同一内容从不同来源复制会分别保留。
- 支持搜索、删除单条记录、清空历史。
- 菜单栏入口和底部 quick panel。
- 支持复制回剪贴板；授权辅助功能权限后可自动粘贴回前台应用。
- 默认最多保留 1000 条历史记录。

## 隐私边界

剪贴板里经常包含 token、密码、代码片段、截图和内部链接。paste3 的当前设计原则是：

- 不上传剪贴板内容。
- 不接入远程分析、遥测或崩溃上报。
- 数据保存在本机 SwiftData 存储中。
- 辅助功能权限只用于把选中的历史项自动粘贴回原前台应用。
- 用户可以从菜单中清空历史记录。

更详细的说明见 [PRIVACY.md](PRIVACY.md)。

## 系统要求

- macOS 14.0 或更高版本。
- Xcode 16 或更高版本。项目使用 SwiftData 和 Swift Testing，建议使用较新的 Xcode。

## 本地开发

克隆仓库后可以直接用 Xcode 打开：

```bash
open paste3.xcodeproj
```

命令行运行单元测试：

```bash
xcodebuild test \
  -project paste3.xcodeproj \
  -scheme paste3 \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/paste3-derived-unit \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:paste3Tests \
  -skip-testing:paste3UITests
```

`DEVELOPMENT_TEAM` 在仓库中保持为空。需要本地签名、Archive 或发布时，请在 Xcode 中配置自己的 Apple Developer Team。

## 权限说明

paste3 读取系统剪贴板不需要额外授权。自动粘贴到前台应用需要 macOS 辅助功能权限，因为它会模拟 `Cmd+V`。

如果不授予辅助功能权限，仍然可以使用历史浏览和复制回剪贴板，只是不会自动向目标应用发送粘贴快捷键。

## 发布状态

目前还没有正式二进制发布。建议开发者先从源码构建运行。正式发布前还需要补充签名、notarization、安装包或 Homebrew Cask 流程。

## 贡献

贡献前请先阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。安全或隐私问题请按 [SECURITY.md](SECURITY.md) 处理，不要在公开 issue 里粘贴真实敏感剪贴板内容。

## 许可证

本项目使用 MIT License，见 [LICENSE](LICENSE)。
