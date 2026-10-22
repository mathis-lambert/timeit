import SwiftUI

/// What a glass surface is for. Glass marks what floats or what is live; content stays opaque.
/// No view applies `glassEffect` directly; everything goes through `glass(_:tint:radius:)`.
enum GlassRole {
    /// What is live or chosen right now: the running timer, the palette's highlighted command.
    case selection
    /// Anything floating over the window: the command palette.
    case panel
}

extension View {
    /// Liquid Glass on the view, in a continuous rounded rectangle. With Reduce Transparency it becomes an
    /// opaque fill with a hairline.
    func glass(_ role: GlassRole, tint: Color? = nil, radius: CGFloat) -> some View {
        modifier(GlassSurface(role: role, tint: tint, radius: radius))
    }

    /// A fine accent ring and faint halo around a floating panel. When the panel appears, one band of light
    /// crosses it from bottom to top; afterwards it stays still and draws nothing that moves.
    func lightRing(_ color: Color, radius: CGFloat) -> some View {
        modifier(LightRing(color: color, radius: radius))
    }

    /// Marks what is running with a selection lens tinted with the project color.
    func liveLens(_ tint: Color, radius: CGFloat) -> some View {
        background { Color.clear.glass(.selection, tint: tint, radius: radius) }
    }

    /// For panels over the window: the command palette.
    func panelShadow() -> some View { shadow(color: .black.opacity(0.16), radius: 32, y: 16) }
}

private struct GlassSurface: ViewModifier {
    let role: GlassRole
    let tint: Color?
    let radius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var scheme

    @ViewBuilder func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if reduceTransparency {
            content.background { shape.fill(opaqueFill).overlay { shape.strokeBorder(Theme.hairline) } }
        } else {
            content.glassEffect(glass, in: shape)
        }
    }

    private var glass: Glass {
        switch role {
        case .selection: .regular.tint(tint?.opacity(scheme == .dark ? 0.26 : 0.14)).interactive()
        case .panel: .regular
        }
    }

    private var opaqueFill: Color {
        switch role {
        case .selection: (tint ?? .primary).opacity(scheme == .dark ? 0.22 : 0.12)
        case .panel: Color(nsColor: .windowBackgroundColor)
        }
    }
}

private struct LightRing: ViewModifier {
    let color: Color
    let radius: CGFloat
    @State private var crossing: Double = 0
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                if !reduceTransparency {
                    shape.fill(color.opacity(0.12)).blur(radius: 18).padding(-2).allowsHitTesting(false)
                }
            }
            .overlay {
                shape.strokeBorder(color.opacity(reduceTransparency ? 0.6 : 0.4), lineWidth: 1)
                    .modifier(LightBand(progress: crossing, color: color, shape: shape))
                    .allowsHitTesting(false)
            }
            .onAppear {
                guard !reduceMotion else { return }
                crossing = 0
                withAnimation(.timingCurve(0.15, 0.9, 0.3, 1, duration: 0.9)) { crossing = 1 }
            }
    }
}

/// A brighter band travelling up the ring. Driven by one animatable value, so it only renders while it runs.
private struct LightBand: ViewModifier, Animatable {
    var progress: Double
    let color: Color
    let shape: RoundedRectangle
    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content.overlay {
            if progress > 0 && progress < 1 {
                let light = color.mix(with: .white, by: 0.5)
                let center = progress
                shape.strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: light.opacity(0), location: max(0, center - 0.3)),
                            .init(color: light, location: center),
                            .init(color: light.opacity(0), location: min(1, center + 0.3)),
                        ],
                        startPoint: .bottom, endPoint: .top),
                    lineWidth: 1.5
                )
                .opacity(sin(.pi * progress))
            }
        }
    }
}
