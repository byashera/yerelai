import SwiftUI

// MARK: - Official Apple iOS 26-27 Liquid Glass Modifiers with iOS 17-18 Material Fallback

struct SenGlassCapsuleModifier: ViewModifier {
    var interactive: Bool = true
    var tintColor: Color? = nil

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content
                .contentShape(Capsule())
                .glassEffect(resolvedGlass, in: .capsule)
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    #if compiler(>=6.2)
    @available(iOS 26.0, *)
    private var resolvedGlass: Glass {
        var g: Glass = .regular
        if let tintColor {
            g = g.tint(tintColor)
        }
        if interactive {
            g = g.interactive()
        }
        return g
    }
    #endif

    @ViewBuilder
    private func fallback(_ content: Content) -> some View {
        content
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        if let tintColor {
                            Capsule().fill(tintColor.opacity(0.14))
                        }
                    }
                    .overlay {
                        Capsule().strokeBorder(.primary.opacity(0.12), lineWidth: 0.6)
                    }
            }
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.10), radius: 10, y: 4)
    }
}

struct SenGlassCircleModifier: ViewModifier {
    var interactive: Bool = true
    var tintColor: Color? = nil

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content
                .contentShape(Circle())
                .glassEffect(resolvedGlass, in: .circle)
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    #if compiler(>=6.2)
    @available(iOS 26.0, *)
    private var resolvedGlass: Glass {
        var g: Glass = .regular
        if let tintColor {
            g = g.tint(tintColor)
        }
        if interactive {
            g = g.interactive()
        }
        return g
    }
    #endif

    @ViewBuilder
    private func fallback(_ content: Content) -> some View {
        content
            .background {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        if let tintColor {
                            Circle().fill(tintColor.opacity(0.18))
                        }
                    }
                    .overlay {
                        Circle().strokeBorder(.primary.opacity(0.12), lineWidth: 0.6)
                    }
            }
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.10), radius: 8, y: 3)
    }
}

struct SenGlassRoundedModifier: ViewModifier {
    var radius: CGFloat = 24
    var interactive: Bool = false

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content
                .contentShape(.rect(cornerRadius: radius))
                .glassEffect(interactive ? .regular.interactive() : .regular, in: .rect(cornerRadius: radius))
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    @ViewBuilder
    private func fallback(_ content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(.primary.opacity(0.12), lineWidth: 0.6)
                    }
            }
            .clipShape(.rect(cornerRadius: radius))
            .shadow(color: .black.opacity(0.12), radius: 14, y: 5)
    }
}

struct SenSoftScrollEdgeModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectStyle(.soft, for: .all)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

struct SenGlassContainer<Content: View>: View {
    var spacing: CGFloat = 10
    @ViewBuilder var content: () -> Content

    var body: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
        #else
        content()
        #endif
    }
}

extension View {
    func senGlassCapsule(interactive: Bool = true, tint: Color? = nil) -> some View {
        modifier(SenGlassCapsuleModifier(interactive: interactive, tintColor: tint))
    }

    func senGlassCircle(interactive: Bool = true, tint: Color? = nil) -> some View {
        modifier(SenGlassCircleModifier(interactive: interactive, tintColor: tint))
    }

    func senGlassRounded(radius: CGFloat = 24, interactive: Bool = false) -> some View {
        modifier(SenGlassRoundedModifier(radius: radius, interactive: interactive))
    }

    func senSoftScrollEdge() -> some View {
        modifier(SenSoftScrollEdgeModifier())
    }
}

// MARK: - Ambient Backdrop (gives iOS 26 Liquid Glass real subtle gradients to refract)

struct SenAmbientBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            if colorScheme == .dark {
                LinearGradient(
                    colors: [
                        Color(red: 0.048, green: 0.068, blue: 0.125),
                        Color(red: 0.065, green: 0.092, blue: 0.172),
                        Color(red: 0.044, green: 0.062, blue: 0.115),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RadialGradient(
                    colors: [Color(red: 0.18, green: 0.48, blue: 1.0).opacity(0.20), Color.clear],
                    center: .topLeading,
                    startRadius: 20,
                    endRadius: 440
                )
                RadialGradient(
                    colors: [Color(red: 0.56, green: 0.28, blue: 0.96).opacity(0.16), Color.clear],
                    center: .bottomTrailing,
                    startRadius: 20,
                    endRadius: 400
                )
                RadialGradient(
                    colors: [Color(red: 0.08, green: 0.72, blue: 0.66).opacity(0.08), Color.clear],
                    center: .center,
                    startRadius: 10,
                    endRadius: 340
                )
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.976, green: 0.976, blue: 0.970),
                        Color(red: 0.962, green: 0.968, blue: 0.985),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RadialGradient(
                    colors: [Color(red: 0.22, green: 0.52, blue: 0.98).opacity(0.08), Color.clear],
                    center: .topLeading,
                    startRadius: 16,
                    endRadius: 420
                )
                RadialGradient(
                    colors: [Color(red: 0.55, green: 0.36, blue: 0.96).opacity(0.06), Color.clear],
                    center: .bottomTrailing,
                    startRadius: 20,
                    endRadius: 390
                )
            }
        }
        .ignoresSafeArea()
    }
}

enum SenHaptics {
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

struct SenPrismOrb: View {
    var size: CGFloat = 68
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var breathe: Bool = false
    @State private var spinCW: Bool = false
    @State private var spinCCW: Bool = false

    var body: some View {
        ZStack {
            // Soft Multi-Tone Aurora Bloom
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.22, green: 0.74, blue: 0.97).opacity(breathe ? 0.34 : 0.20),
                            Color(red: 0.39, green: 0.40, blue: 0.95).opacity(breathe ? 0.24 : 0.14),
                            Color(red: 0.85, green: 0.27, blue: 0.94).opacity(0.10),
                            Color.clear,
                        ],
                        center: .center,
                        startRadius: 4,
                        endRadius: size * 0.92
                    )
                )
                .frame(width: size * 1.75, height: size * 1.75)
                .scaleEffect(breathe ? 1.09 : 0.94)

            // Outer Dashed Orbital Ring
            Circle()
                .stroke(
                    Color.indigo.opacity(colorScheme == .dark ? 0.36 : 0.24),
                    style: StrokeStyle(lineWidth: 1.3, dash: [4, 5])
                )
                .frame(width: size * 1.32, height: size * 1.32)
                .rotationEffect(.degrees(spinCW ? 360 : 0))

            // Inner Luminous Arc Ring
            Circle()
                .trim(from: 0.08, to: 0.56)
                .stroke(
                    LinearGradient(
                        colors: [Color.cyan.opacity(0.82), Color.indigo.opacity(0.55), Color.clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 1.6, lineCap: .round)
                )
                .frame(width: size * 1.14, height: size * 1.14)
                .rotationEffect(.degrees(spinCCW ? -360 : 0))

            // Floating Frosted Prism Medallion
            RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                .fill(
                    colorScheme == .dark
                        ? LinearGradient(colors: [Color(red: 0.13, green: 0.17, blue: 0.28), Color(red: 0.08, green: 0.11, blue: 0.20)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient(colors: [Color.white.opacity(0.95), Color(red: 0.94, green: 0.96, blue: 0.99)], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: size, height: size)
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.cyan.opacity(0.55), Color.indigo.opacity(0.35), Color.pink.opacity(0.38)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.2
                        )
                }
                .shadow(color: Color.indigo.opacity(colorScheme == .dark ? 0.34 : 0.16), radius: 18, y: 7)
                .offset(y: breathe ? -3 : 2)

            // Animated 4-Point Aether Star Core
            Image(systemName: "sparkle")
                .font(.system(size: size * 0.44, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(red: 0.22, green: 0.74, blue: 0.97), Color(red: 0.39, green: 0.40, blue: 0.95), Color(red: 0.85, green: 0.27, blue: 0.94)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .scaleEffect(breathe ? 1.08 : 0.94)
                .offset(y: breathe ? -3 : 2)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                breathe = true
            }
            withAnimation(.linear(duration: 22).repeatForever(autoreverses: false)) {
                spinCW = true
            }
            withAnimation(.linear(duration: 11).repeatForever(autoreverses: false)) {
                spinCCW = true
            }
        }
    }
}

struct SenStreamingDot: View {
    @State private var pulse = false
    var body: some View {
        Circle()
            .fill(Color.blue)
            .frame(width: 8, height: 8)
            .scaleEffect(pulse ? 1.25 : 0.78)
            .opacity(pulse ? 1.0 : 0.45)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

struct SenSpringButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.26, dampingFraction: 0.72), value: configuration.isPressed)
    }
}
