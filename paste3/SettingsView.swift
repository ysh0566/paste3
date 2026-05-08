//
//  SettingsView.swift
//  paste3
//
//  Created by Codex on 2026/5/8.
//

#if os(macOS)
import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ClipboardItem.createdAt, order: .reverse) private var items: [ClipboardItem]

    @State private var selectedTab: SettingsTab = .general
    @State private var selectedShortcutID = QuickPanelShortcutPreference.shared.shortcut.id
    @State private var accessibilityTrusted = AccessibilityPermission.isTrusted
    @State private var isConfirmingHistoryClear = false

    private var colors: SettingsColors {
        SettingsColors(colorScheme: colorScheme)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Divider()

            mainContent
        }
        .frame(width: 900, height: 640)
        .background(colors.windowBackground)
        .onAppear(perform: refreshState)
        .onChange(of: selectedShortcutID) { _, shortcutID in
            QuickPanelShortcutPreference.shared.setShortcut(QuickPanelShortcut.find(id: shortcutID))
        }
        .confirmationDialog(
            "清空剪贴板历史？",
            isPresented: $isConfirmingHistoryClear,
            titleVisibility: .visible
        ) {
            Button("清空历史", role: .destructive, action: clearHistory)
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会删除 paste3 在本机保存的所有剪贴板项目。")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            windowDots
                .padding(.top, 20)
                .padding(.horizontal, 24)
                .padding(.bottom, 22)

            VStack(spacing: 6) {
                ForEach(SettingsTab.primaryTabs) { tab in
                    SettingsSidebarButton(
                        tab: tab,
                        isSelected: selectedTab == tab,
                        colors: colors
                    ) {
                        selectedTab = tab
                    }
                }
            }
            .padding(.horizontal, 18)

            Spacer()

            SettingsSidebarButton(
                tab: .help,
                isSelected: selectedTab == .help,
                colors: colors
            ) {
                selectedTab = .help
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 28)
        }
        .frame(width: 250)
        .background(colors.sidebarBackground)
    }

    private var windowDots: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(red: 1.0, green: 0.37, blue: 0.35))
                .frame(width: 14, height: 14)
            Circle()
                .fill(Color(red: 1.0, green: 0.76, blue: 0.18))
                .frame(width: 14, height: 14)
            Circle()
                .fill(Color(red: 0.78, green: 0.79, blue: 0.80))
                .frame(width: 14, height: 14)
        }
    }

    private var mainContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text(selectedTab.title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(colors.primaryText)
                    .padding(.top, 32)

                selectedContent
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 34)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background(colors.contentBackground)
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedTab {
        case .general:
            generalContent
        case .privacy:
            privacyContent
        case .keyboard:
            keyboardContent
        case .history:
            historyContent
        case .help:
            helpContent
        }
    }

    private var generalContent: some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingsCard(colors: colors) {
                SettingsInfoRow(
                    title: "菜单栏运行",
                    detail: "paste3 作为菜单栏工具运行，左键打开 Quick Panel，右键打开菜单。",
                    trailing: Text("已开启")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(colors.secondaryText),
                    colors: colors
                )

                SettingsDivider(colors: colors)

                SettingsInfoRow(
                    title: "快速面板",
                    detail: "从屏幕底部打开剪贴板历史，选择项目后可复制或自动粘贴。",
                    trailing: Button("打开") {
                        QuickPanelController.shared.show()
                    }
                    .font(.system(size: 12, weight: .medium)),
                    colors: colors
                )

                SettingsDivider(colors: colors)

                SettingsInfoRow(
                    title: "本机存储",
                    detail: "剪贴板历史只保存在这台 Mac 上。",
                    trailing: Text("\(items.count)/\(ClipboardStore.defaultMaxItems)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(colors.secondaryText),
                    colors: colors
                )
            }

            sectionTitle("粘贴项目")

            SettingsCard(colors: colors) {
                SettingsInfoRow(
                    title: "到当前活动应用",
                    detail: "选中项目后写回系统剪贴板，并在授权后自动粘贴到当前应用。",
                    trailing: Image(systemName: "target")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(colors.accent),
                    colors: colors
                )

                SettingsDivider(colors: colors)

                SettingsInfoRow(
                    title: "保留原始内容",
                    detail: "文本、链接、命令、图片、文件和富文本会尽量按原格式保存。",
                    trailing: Image(systemName: "checkmark.square.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(colors.accent),
                    colors: colors
                )
            }
        }
    }

    private var privacyContent: some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingsCard(colors: colors) {
                SettingsInfoRow(
                    title: "辅助功能权限",
                    detail: accessibilityTrusted
                        ? "已允许 paste3 在选择历史项目后向当前应用发送 Cmd+V。"
                        : "自动粘贴需要该权限；未授权时仍可复制回系统剪贴板。",
                    trailing: Button(accessibilityTrusted ? "已授权" : "授权") {
                        requestAccessibilityPermission()
                    }
                    .font(.system(size: 12, weight: .medium))
                    .disabled(accessibilityTrusted),
                    colors: colors
                )
            }

            sectionTitle("隐私")

            SettingsCard(colors: colors) {
                SettingsInfoRow(
                    title: "本地优先",
                    detail: "当前版本不上传剪贴板历史，也不依赖远程账号同步。",
                    trailing: Image(systemName: "lock.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(colors.accent),
                    colors: colors
                )
            }
        }
    }

    private var keyboardContent: some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingsCard(colors: colors) {
                SettingsInfoRow(
                    title: "Quick Panel 快捷键",
                    detail: "选择全局快捷键，用于在任意应用上方呼出 paste3。",
                    trailing: Picker("快捷键", selection: $selectedShortcutID) {
                        ForEach(QuickPanelShortcut.all) { shortcut in
                            Text(shortcut.menuTitle).tag(shortcut.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 190),
                    colors: colors
                )
            }
        }
    }

    private var historyContent: some View {
        VStack(alignment: .leading, spacing: 28) {
            sectionTitle("保留历史")

            SettingsCard(colors: colors) {
                VStack(alignment: .leading, spacing: 14) {
                    Slider(
                        value: .constant(Double(items.count)),
                        in: 0...Double(ClipboardStore.defaultMaxItems)
                    )
                    .disabled(true)
                    .tint(colors.accent)

                    HStack {
                        Text("0")
                        Spacer()
                        Text("\(ClipboardStore.defaultMaxItems)")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(colors.primaryText)
                }

                SettingsDivider(colors: colors)

                HStack {
                    Text("\(items.count) 个项目保存在本机")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(colors.primaryText)

                    Spacer()

                    Button(role: .destructive) {
                        isConfirmingHistoryClear = true
                    } label: {
                        Text("删除历史...")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .disabled(items.isEmpty)
                }
            }
        }
    }

    private var helpContent: some View {
        SettingsCard(colors: colors) {
            SettingsInfoRow(
                title: "帮助中心",
                detail: "复制内容后，用菜单栏图标或快捷键打开 Quick Panel；方向键选择，回车粘贴。",
                trailing: Image(systemName: "questionmark.circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(colors.secondaryText),
                colors: colors
            )
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(colors.primaryText)
    }

    private func refreshState() {
        selectedShortcutID = QuickPanelShortcutPreference.shared.shortcut.id
        accessibilityTrusted = AccessibilityPermission.isTrusted
    }

    private func requestAccessibilityPermission() {
        AccessibilityPermission.requestPromptAndOpenSettingsIfNeeded()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            accessibilityTrusted = AccessibilityPermission.isTrusted
        }
    }

    private func clearHistory() {
        do {
            try ClipboardStore(modelContext: modelContext).deleteAll()
        } catch {
            assertionFailure("Failed to clear clipboard history: \(error)")
        }
    }
}

private enum SettingsTab: CaseIterable, Identifiable {
    case general
    case privacy
    case keyboard
    case history
    case help

    var id: Self { self }

    static var primaryTabs: [SettingsTab] {
        allCases.filter { $0 != .help }
    }

    var title: String {
        switch self {
        case .general:
            "通用"
        case .privacy:
            "隐私"
        case .keyboard:
            "键盘快捷键"
        case .history:
            "保留历史"
        case .help:
            "帮助中心"
        }
    }

    var icon: String {
        switch self {
        case .general:
            "gearshape"
        case .privacy:
            "hand.raised"
        case .keyboard:
            "keyboard"
        case .history:
            "clock.arrow.circlepath"
        case .help:
            "questionmark.circle"
        }
    }
}

private struct SettingsSidebarButton: View {
    let tab: SettingsTab
    let isSelected: Bool
    let colors: SettingsColors
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: tab.icon)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 20)

                Text(tab.title)
                    .font(.system(size: 14, weight: .semibold))

                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? Color.white : colors.primaryText)
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? colors.accent : Color.clear)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsCard<Content: View>: View {
    let colors: SettingsColors
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0, content: content)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(colors.cardBackground)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(colors.border, lineWidth: 0.7)
            }
    }
}

private struct SettingsInfoRow<Trailing: View>: View {
    let title: String
    let detail: String
    let trailing: Trailing
    let colors: SettingsColors

    init(
        title: String,
        detail: String,
        trailing: Trailing,
        colors: SettingsColors
    ) {
        self.title = title
        self.detail = detail
        self.trailing = trailing
        self.colors = colors
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(colors.primaryText)

                Text(detail)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 24)

            trailing
        }
        .frame(minHeight: 50)
    }
}

private struct SettingsDivider: View {
    let colors: SettingsColors

    var body: some View {
        Rectangle()
            .fill(colors.border)
            .frame(height: 0.7)
            .padding(.vertical, 8)
    }
}

private struct SettingsColors {
    let windowBackground: Color
    let sidebarBackground: Color
    let contentBackground: Color
    let cardBackground: Color
    let border: Color
    let primaryText: Color
    let secondaryText: Color
    let accent: Color

    init(colorScheme: ColorScheme) {
        if colorScheme == .dark {
            windowBackground = Color(red: 0.08, green: 0.08, blue: 0.085)
            sidebarBackground = Color(red: 0.10, green: 0.10, blue: 0.11)
            contentBackground = Color(red: 0.075, green: 0.075, blue: 0.08)
            cardBackground = Color.white.opacity(0.055)
            border = Color.white.opacity(0.10)
            primaryText = Color(red: 0.92, green: 0.92, blue: 0.94)
            secondaryText = Color(red: 0.64, green: 0.65, blue: 0.69)
            accent = Color(red: 0.13, green: 0.47, blue: 0.96)
        } else {
            windowBackground = Color(red: 0.965, green: 0.965, blue: 0.972)
            sidebarBackground = Color(red: 0.957, green: 0.957, blue: 0.965)
            contentBackground = Color(red: 0.988, green: 0.988, blue: 0.992)
            cardBackground = Color.white.opacity(0.92)
            border = Color.black.opacity(0.08)
            primaryText = Color(red: 0.13, green: 0.13, blue: 0.15)
            secondaryText = Color(red: 0.46, green: 0.46, blue: 0.50)
            accent = Color(red: 0.0, green: 0.43, blue: 0.95)
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: ClipboardItem.self, inMemory: true)
}
#endif
