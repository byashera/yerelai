import SwiftUI

@main
struct SENAIApp: App {
    @StateObject private var server = ServerManager()
    @AppStorage("senai_theme") private var themePref: String = "light"

    private let previewScreen: String?
    private let autoPin: String?
    private let autoPrompt: String?

    init() {
        let args = ProcessInfo.processInfo.arguments
        func argVal(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        self.previewScreen = argVal("--preview-screen")
        self.autoPin = argVal("--auto-pin")
        self.autoPrompt = argVal("--auto-prompt")
    }

    var body: some Scene {
        WindowGroup {
            RootContainerView(previewScreen: previewScreen)
                .environmentObject(server)
                .preferredColorScheme(resolvedColorScheme)
                .task {
                    if let previewScreen {
                        server.applyPreviewState(screen: previewScreen)
                        return
                    }
                    await server.bootstrap()
                    if let pin = autoPin, !pin.isEmpty, server.requiresPin {
                        await server.verifyPin(pin)
                    }
                    if let prompt = autoPrompt, !prompt.isEmpty, !server.requiresPin, !server.activeBaseURL.isEmpty {
                        try? await Task.sleep(for: .milliseconds(600))
                        server.sendMessage(prompt)
                    }
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
    let previewScreen: String?

    var body: some View {
        ChatView(initialPreviewScreen: previewScreen)
    }
}
