import SwiftUI

@main
struct SENAIApp: App {
    @StateObject private var server = ServerManager()
    @AppStorage("senai_theme") private var themePref: String = "system"

    var body: some Scene {
        WindowGroup {
            RootContainerView()
                .environmentObject(server)
                .preferredColorScheme(resolvedColorScheme)
                .task {
                    await server.bootstrap()
                }
        }
    }

    private var resolvedColorScheme: ColorScheme? {
        switch themePref {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
    }
}

struct RootContainerView: View {
    @EnvironmentObject private var server: ServerManager

    var body: some View {
        ZStack {
            ChatView()
            if server.requiresPin {
                PinLockView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: server.requiresPin)
    }
}
