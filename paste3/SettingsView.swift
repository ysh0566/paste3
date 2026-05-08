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
    @State private var selectedRetentionPeriodID = ClipboardRetentionPreference.shared.period.id
    @State private var accessibilityTrusted = AccessibilityPermission.isTrusted
    @State private var isConfirmingHistoryClear = false

    private var colors: SettingsColors {
        SettingsColors(colorScheme: colorScheme)
    }

    var body: some View {
        ZStack {
            Paste3LiquidBackdrop(palette: colors.palette)

            HStack(spacing: 0) {
                sidebar

                Rectangle()
                    .fill(colors.edgeHighlight.opacity(colorScheme == .dark ? 0.12 : 0.42))
                    .frame(width: 0.7)

                mainContent
            }
        }
        .frame(width: 900, height: 640)
        .onAppear(perform: refreshState)
        .onChange(of: selectedShortcutID) { _, shortcutID in
            QuickPanelShortcutPreference.shared.setShortcut(QuickPanelShortcut.find(id: shortcutID))
        }
        .onChange(of: selectedRetentionPeriodID) { _, periodID in
            updateRetentionPeriod(ClipboardRetentionPeriod.find(id: periodID))
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
            sidebarHeader
                .padding(.top, 52)
                .padding(.horizontal, 24)
                .padding(.bottom, 18)

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
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay {
                    LinearGradient(
                        colors: [
                            colors.edgeHighlight.opacity(colorScheme == .dark ? 0.06 : 0.28),
                            colors.sidebarBackground,
                            colors.glow.opacity(0.16)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        }
    }

    private var sidebarHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(colors.accent)
                .frame(width: 30, height: 30)
                .paste3GlassSurface(
                    cornerRadius: 12,
                    fill: colors.controlBackground.opacity(0.48)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("paste3")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(colors.primaryText)

                Text("设置")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(colors.secondaryText)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .paste3GlassSurface(
            cornerRadius: Paste3Theme.controlRadius,
            fill: colors.cardBackground.opacity(0.28)
        )
    }

    private var mainContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text(selectedTab.title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [colors.primaryText, colors.secondaryText],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .padding(.top, 32)

                selectedContent
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 34)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay {
                    LinearGradient(
                        colors: [
                            colors.contentBackground.opacity(0.74),
                            colors.glow.opacity(0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        }
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
                    trailingStyle: .button,
                    colors: colors
                )

                SettingsDivider(colors: colors)

                SettingsInfoRow(
                    title: "本机存储",
                    detail: "\(ClipboardRetentionPreference.shared.period.detail)，并且只保存在这台 Mac 上。",
                    trailing: Text("\(items.count) 项")
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
                    trailingStyle: .button,
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
                    trailingStyle: .picker,
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
                        value: retentionPeriodIndexBinding,
                        in: 0...Double(ClipboardRetentionPeriod.all.count - 1),
                        step: 1
                    )
                    .tint(colors.accent)

                    RetentionScaleLabels(colors: colors)

                    Text(selectedRetentionPeriod.detail)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(colors.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentTransition(.numericText())
                }

                SettingsDivider(colors: colors)

                HStack {
                    Text("当前档位")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(colors.secondaryText)

                    Spacer()

                    Text(selectedRetentionPeriod.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(colors.primaryText)
                }

                SettingsDivider(colors: colors)

                HStack {
                    Text("\(items.count) 个项目保存在本机")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(colors.primaryText)

                    Spacer()

                    Button(role: .destructive) {
                        isConfirmingHistoryClear = true
                    } label: {
                        Text("删除历史...")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .buttonStyle(SettingsGlassButtonStyle(colors: colors, isDestructive: true))
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
            .foregroundStyle(colors.secondaryText)
    }

    private func refreshState() {
        selectedShortcutID = QuickPanelShortcutPreference.shared.shortcut.id
        selectedRetentionPeriodID = ClipboardRetentionPreference.shared.period.id
        accessibilityTrusted = AccessibilityPermission.isTrusted
        pruneHistory(using: ClipboardRetentionPreference.shared.period)
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

    private var selectedRetentionPeriod: ClipboardRetentionPeriod {
        ClipboardRetentionPeriod.find(id: selectedRetentionPeriodID)
    }

    private var retentionPeriodIndexBinding: Binding<Double> {
        Binding {
            Double(ClipboardRetentionPeriod.index(forID: selectedRetentionPeriodID))
        } set: { value in
            let index = min(
                max(Int(value.rounded()), 0),
                ClipboardRetentionPeriod.all.count - 1
            )
            selectedRetentionPeriodID = ClipboardRetentionPeriod.all[index].id
        }
    }

    private func updateRetentionPeriod(_ period: ClipboardRetentionPeriod) {
        ClipboardRetentionPreference.shared.setPeriod(period)
        pruneHistory(using: period)
    }

    private func pruneHistory(using period: ClipboardRetentionPeriod) {
        do {
            try ClipboardStore(modelContext: modelContext, retentionPeriod: period).pruneExpiredItemsIfNeeded()
        } catch {
            assertionFailure("Failed to prune expired clipboard history: \(error)")
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
            .foregroundStyle(isSelected ? colors.selectedText : colors.primaryText)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 42, maxHeight: 42, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        isSelected
                            ? LinearGradient(
                                colors: [
                                    colors.accent.opacity(0.92),
                                    colors.accent.opacity(0.66),
                                    colors.edgeHighlight.opacity(0.26)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(colors: [.clear], startPoint: .top, endPoint: .bottom)
                    )
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(colors.edgeHighlight.opacity(0.48), lineWidth: 0.8)
                        }
                    }
            }
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsCard<Content: View>: View {
    let colors: SettingsColors
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0, content: content)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .paste3GlassSurface(
                cornerRadius: Paste3Theme.cardRadius,
                fill: colors.cardBackground,
                isProminent: false
            )
            .overlay {
                RoundedRectangle(cornerRadius: Paste3Theme.cardRadius, style: .continuous)
                    .stroke(colors.edgeHighlight.opacity(0.26), lineWidth: 0.8)
            }
    }
}

private enum SettingsTrailingStyle {
    case plain
    case button
    case picker
}

private struct SettingsInfoRow<Trailing: View>: View {
    let title: String
    let detail: String
    let trailing: Trailing
    let trailingStyle: SettingsTrailingStyle
    let colors: SettingsColors

    init(
        title: String,
        detail: String,
        trailing: Trailing,
        trailingStyle: SettingsTrailingStyle = .plain,
        colors: SettingsColors
    ) {
        self.title = title
        self.detail = detail
        self.trailing = trailing
        self.trailingStyle = trailingStyle
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

            styledTrailing
        }
        .frame(minHeight: 50)
    }

    @ViewBuilder
    private var styledTrailing: some View {
        switch trailingStyle {
        case .plain:
            trailing
        case .button:
            trailing
                .buttonStyle(SettingsGlassButtonStyle(colors: colors))
        case .picker:
            trailing
                .padding(.horizontal, 8)
                .frame(height: 34)
                .paste3GlassSurface(
                    cornerRadius: Paste3Theme.controlRadius,
                    fill: colors.controlBackground
                )
        }
    }
}

private struct SettingsDivider: View {
    let colors: SettingsColors

    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [colors.edgeHighlight.opacity(0.45), colors.border.opacity(0.52)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 0.7)
            .padding(.vertical, 8)
    }
}

private struct RetentionScaleLabels: View {
    let colors: SettingsColors

    private let markers: [(title: String, index: Int)] = [
        ("天", 0),
        ("周", 6),
        ("个月", 9),
        ("年", 20),
        ("永久", ClipboardRetentionPeriod.all.count - 1)
    ]

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                ForEach(markers, id: \.title) { marker in
                    Text(marker.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(colors.primaryText)
                        .position(
                            x: markerX(marker.index, width: geometry.size.width),
                            y: 12
                        )
                }
            }
        }
        .frame(height: 24)
    }

    private func markerX(_ index: Int, width: CGFloat) -> CGFloat {
        guard ClipboardRetentionPeriod.all.count > 1 else {
            return 0
        }

        let edgeInset: CGFloat = 20
        let availableWidth = max(width - edgeInset * 2, 0)
        return edgeInset + availableWidth * CGFloat(index) / CGFloat(ClipboardRetentionPeriod.all.count - 1)
    }
}

private struct SettingsGlassButtonStyle: ButtonStyle {
    let colors: SettingsColors
    var isDestructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isDestructive ? colors.destructive : colors.primaryText)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .paste3GlassSurface(
                cornerRadius: Paste3Theme.controlRadius,
                fill: buttonFill(isPressed: configuration.isPressed),
                isProminent: configuration.isPressed
            )
            .contentShape(RoundedRectangle(cornerRadius: Paste3Theme.controlRadius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private func buttonFill(isPressed: Bool) -> Color {
        if isDestructive {
            return colors.destructive.opacity(isPressed ? 0.20 : 0.12)
        }

        return colors.controlBackground.opacity(isPressed ? 0.88 : 0.64)
    }
}

private struct SettingsColors {
    let palette: Paste3Theme.Palette
    let windowBackground: Color
    let sidebarBackground: Color
    let contentBackground: Color
    let cardBackground: Color
    let controlBackground: Color
    let border: Color
    let edgeHighlight: Color
    let glow: Color
    let primaryText: Color
    let secondaryText: Color
    let selectedText: Color
    let accent: Color
    let destructive: Color

    init(colorScheme: ColorScheme) {
        let palette = Paste3Theme.palette(for: colorScheme)
        self.palette = palette

        if colorScheme == .dark {
            windowBackground = palette.background
            sidebarBackground = palette.shellFill.opacity(0.68)
            contentBackground = palette.shellFill.opacity(0.42)
            cardBackground = Color.white.opacity(0.070)
            controlBackground = Color.white.opacity(0.075)
            border = palette.border
            edgeHighlight = palette.edgeHighlight
            glow = palette.glassGlow
            primaryText = palette.text
            secondaryText = palette.secondaryText
            selectedText = palette.primaryText
            accent = palette.primary
            destructive = palette.error
        } else {
            windowBackground = palette.background
            sidebarBackground = palette.shellFill.opacity(0.78)
            contentBackground = Color.white.opacity(0.46)
            cardBackground = Color.white.opacity(0.66)
            controlBackground = Color.white.opacity(0.54)
            border = palette.border
            edgeHighlight = palette.edgeHighlight
            glow = palette.glassGlow
            primaryText = palette.text
            secondaryText = palette.secondaryText
            selectedText = .white
            accent = palette.primary
            destructive = palette.error
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: ClipboardItem.self, inMemory: true)
}
#endif
