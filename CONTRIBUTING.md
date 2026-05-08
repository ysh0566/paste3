# 贡献指南

感谢关注 paste3。这个项目处理剪贴板隐私数据，贡献时请优先保持实现简单、行为可解释、权限边界清晰。

## 开发环境

- macOS 14.0 或更高版本。
- Xcode 16 或更高版本。
- 使用仓库内的 `paste3.xcodeproj`。

本仓库不写死 `DEVELOPMENT_TEAM`。如果需要本地运行签名，请在 Xcode 中配置自己的 Apple Developer Team，不要把个人 team 配置提交进仓库。

## 本地测试

提交前至少运行：

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

如果改动涉及 UI、菜单栏、quick panel 或辅助功能自动粘贴，请同时手动验证一次真实应用流程。

## 代码约定

- 重要分支或难理解逻辑需要加简短注释。
- 避免引入不必要的抽象。
- 剪贴板数据处理要默认按敏感数据对待。
- 不要新增远程网络请求、遥测或分析，除非先明确设计隐私边界。
- 不要提交 `.DS_Store`、DerivedData、xcresult、xcarchive、个人 Xcode 配置。

## PR 建议

PR 描述应包含：

- 改动目的。
- 涉及的用户行为。
- 隐私或权限影响。
- 已运行的测试命令。
- 如果有未验证的部分，请明确写出。

## 安全问题

安全和隐私问题请按 [SECURITY.md](SECURITY.md) 处理。不要在公开 issue 或 PR 中粘贴真实敏感剪贴板内容。
