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
    static let radius: CGFloat = 22
    static let cardRadius: CGFloat = 18
    static let controlRadius: CGFloat = 14

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
        let edgeHighlight: Color
        let glassShadow: Color
        let glassGlow: Color
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
            cardFill: Color.white.opacity(0.075),
            insetFill: Color.white.opacity(0.075),
            border: Color.white.opacity(0.16),
            edgeHighlight: Color.white.opacity(0.42),
            glassShadow: Color.black.opacity(0.46),
            glassGlow: Color(red: 0.36, green: 0.72, blue: 1.0).opacity(0.20),
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
            cardFill: Color.white.opacity(0.64),
            insetFill: Color.white.opacity(0.54),
            border: Color.black.opacity(0.075),
            edgeHighlight: Color.white.opacity(0.92),
            glassShadow: Color.black.opacity(0.14),
            glassGlow: Color(red: 0.18, green: 0.52, blue: 1.0).opacity(0.14),
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
                    VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
#endif
                    LinearGradient(
                        colors: [
                            palette.edgeHighlight.opacity(colorScheme == .dark ? 0.10 : 0.34),
                            palette.shellFill,
                            palette.glassGlow.opacity(colorScheme == .dark ? 0.22 : 0.38)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Paste3Theme.radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Paste3Theme.radius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                palette.edgeHighlight,
                                palette.border,
                                palette.border.opacity(0.45)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.9
                    )
            }
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: Paste3Theme.radius, style: .continuous)
                    .stroke(palette.edgeHighlight.opacity(colorScheme == .dark ? 0.18 : 0.46), lineWidth: 1)
                    .blur(radius: 0.7)
                    .mask(
                        LinearGradient(
                            colors: [.black, .clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            }
            .shadow(
                color: palette.glassShadow,
                radius: 34,
                x: 0,
                y: 18
            )
    }
}

struct Paste3LiquidBackdrop: View {
    let palette: Paste3Theme.Palette

    var body: some View {
        ZStack {
            palette.background

            LinearGradient(
                colors: [
                    palette.primary.opacity(0.18),
                    palette.glassGlow.opacity(0.20),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            LinearGradient(
                colors: [
                    Color.clear,
                    Color(red: 0.78, green: 0.94, blue: 0.86).opacity(0.16),
                    Color(red: 1.0, green: 0.84, blue: 0.54).opacity(0.10)
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
        }
        .ignoresSafeArea()
    }
}

struct Paste3GlassSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let cornerRadius: CGFloat
    let fill: Color
    let isProminent: Bool

    func body(content: Content) -> some View {
        let palette = Paste3Theme.palette(for: colorScheme)

        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(fill)
                    }
                    // Two opposing strokes create the refractive edge that makes
                    // flat controls read as glass without hiding their content.
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(
                                AngularGradient(
                                    colors: [
                                        palette.edgeHighlight,
                                        palette.border.opacity(0.30),
                                        palette.glassGlow.opacity(isProminent ? 0.95 : 0.46),
                                        palette.edgeHighlight.opacity(0.35),
                                        palette.edgeHighlight
                                    ],
                                    center: .center
                                ),
                                lineWidth: isProminent ? 1.2 : 0.8
                            )
                    }
                    .overlay(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(palette.edgeHighlight.opacity(colorScheme == .dark ? 0.14 : 0.52), lineWidth: 1)
                            .blur(radius: 0.45)
                            .padding(1)
                            .mask(
                                LinearGradient(
                                    colors: [.black, .clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .shadow(
                        color: palette.glassShadow.opacity(isProminent ? 0.76 : 0.46),
                        radius: isProminent ? 18 : 10,
                        x: 0,
                        y: isProminent ? 10 : 5
                    )
            }
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

    func paste3GlassSurface(
        cornerRadius: CGFloat,
        fill: Color,
        isProminent: Bool = false
    ) -> some View {
        modifier(Paste3GlassSurface(cornerRadius: cornerRadius, fill: fill, isProminent: isProminent))
    }
}
