//
//  Paste3Theme.swift
//  paste3
//
//  Created by Codex on 2026/5/7.
//

#if os(macOS)
import AppKit
#endif
import SwiftUI

enum Paste3Theme {
    static let margin: CGFloat = 24
    static let gutter: CGFloat = 12
    static let radius: CGFloat = 12
    static let controlRadius: CGFloat = 8

    static let success = Color(red: 0.196, green: 0.843, blue: 0.294)

    static func palette(for colorScheme: ColorScheme) -> Palette {
        colorScheme == .dark ? .dark : .light
    }

    struct Palette {
        let background: Color
        let shellFill: Color
        let topBarFill: Color
        let cardFill: Color
        let insetFill: Color
        let border: Color
        let text: Color
        let secondaryText: Color
        let tertiaryText: Color
        let primary: Color
        let primaryText: Color
        let error: Color

        static let dark = Palette(
            background: Color(red: 0.02, green: 0.02, blue: 0.02),
            shellFill: Color(red: 0.075, green: 0.075, blue: 0.075).opacity(0.76),
            topBarFill: Color(red: 0.125, green: 0.125, blue: 0.125).opacity(0.45),
            cardFill: Color.white.opacity(0.055),
            insetFill: Color(red: 0.02, green: 0.02, blue: 0.02).opacity(0.22),
            border: Color.white.opacity(0.14),
            text: Color(red: 0.9, green: 0.89, blue: 0.88),
            secondaryText: Color(red: 0.76, green: 0.78, blue: 0.84),
            tertiaryText: Color(red: 0.55, green: 0.56, blue: 0.62),
            primary: Color(red: 0.68, green: 0.78, blue: 1.0),
            primaryText: Color(red: 0.0, green: 0.18, blue: 0.41),
            error: Color(red: 1.0, green: 0.71, blue: 0.67)
        )

        static let light = Palette(
            background: Color(red: 0.98, green: 0.98, blue: 0.996),
            shellFill: Color(red: 0.98, green: 0.976, blue: 0.996).opacity(0.72),
            topBarFill: Color(red: 0.933, green: 0.929, blue: 0.953).opacity(0.58),
            cardFill: Color.white.opacity(0.58),
            insetFill: Color(red: 0.957, green: 0.953, blue: 0.973),
            border: Color.black.opacity(0.08),
            text: Color(red: 0.102, green: 0.106, blue: 0.122),
            secondaryText: Color(red: 0.255, green: 0.278, blue: 0.333),
            tertiaryText: Color(red: 0.443, green: 0.467, blue: 0.525),
            primary: Color(red: 0.0, green: 0.345, blue: 0.737),
            primaryText: .white,
            error: Color(red: 0.729, green: 0.102, blue: 0.102)
        )
    }
}

struct Paste3GlassShell: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let palette = Paste3Theme.palette(for: colorScheme)

        content
            .background {
                ZStack {
#if os(macOS)
                    VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
#endif
                    palette.shellFill
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Paste3Theme.radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Paste3Theme.radius, style: .continuous)
                    .stroke(palette.border, lineWidth: 0.5)
            }
            .shadow(
                color: colorScheme == .dark ? .black.opacity(0.42) : .black.opacity(0.12),
                radius: 30,
                x: 0,
                y: 16
            )
    }
}

#if os(macOS)
// SwiftUI materials do not expose the same blending controls as NSVisualEffectView,
// so the shared glass shell bridges AppKit for a closer macOS utility-window feel.
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
    }
}
#endif

extension View {
    func paste3GlassShell() -> some View {
        modifier(Paste3GlassShell())
    }
}
