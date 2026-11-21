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
                Color(red: 0.08, green: 0.09, blue: 0.11)
                RadialGradient(
                    colors: [Color.blue.opacity(0.12), Color.clear],
                    center: .topLeading,
                    startRadius: 20,
                    endRadius: 420
                )
                RadialGradient(
                    colors: [Color.indigo.opacity(0.10), Color.clear],
                    center: .bottomTrailing,
                    startRadius: 20,
                    endRadius: 380
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
