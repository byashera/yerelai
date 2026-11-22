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
                        Color(red: 0.055, green: 0.086, blue: 0.155),
                        Color(red: 0.075, green: 0.112, blue: 0.205),
                        Color(red: 0.050, green: 0.078, blue: 0.140),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RadialGradient(
                    colors: [Color(red: 0.20, green: 0.45, blue: 1.0).opacity(0.18), Color.clear],
                    center: .topLeading,
                    startRadius: 20,
                    endRadius: 440
                )
                RadialGradient(
                    colors: [Color(red: 0.48, green: 0.30, blue: 0.96).opacity(0.15), Color.clear],
                    center: .bottomTrailing,
                    startRadius: 20,
                    endRadius: 400
                )
            } else {
                Color(red: 0.969, green: 0.961, blue: 0.941) // Warm studio cream
                RadialGradient(
                    colors: [Color.blue.opacity(0.06), Color.clear],
                    center: .topLeading,
                    startRadius: 20,
                    endRadius: 420
                )
                RadialGradient(
                    colors: [Color.orange.opacity(0.05), Color.clear],
                    center: .bottomTrailing,
                    startRadius: 20,
                    endRadius: 380
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
    @State private var breathe: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.blue.opacity(breathe ? 0.38 : 0.24), Color.indigo.opacity(0.14), Color.clear],
                        center: .center,
                        startRadius: 4,
                        endRadius: size * 0.76
                    )
                )
                .frame(width: size * 1.44, height: size * 1.44)
                .scaleEffect(breathe ? 1.06 : 0.96)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.14, green: 0.36, blue: 0.92), Color(red: 0.32, green: 0.22, blue: 0.84)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .overlay {
                    Circle().strokeBorder(.white.opacity(0.32), lineWidth: 1)
                }
                .shadow(color: Color.blue.opacity(0.34), radius: 18, y: 6)

            Image(systemName: "diamond.fill")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(colors: [.white, Color.cyan.opacity(0.88)], startPoint: .top, endPoint: .bottom)
                )
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
                breathe = true
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
