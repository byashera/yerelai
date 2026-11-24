import ActivityKit
import Foundation
import UIKit
import UserNotifications

@MainActor
final class LiveNotificationManager {
    static let shared = LiveNotificationManager()

    private var currentActivity: Activity<SenGenerationAttributes>?
    private var bgTaskId: UIBackgroundTaskIdentifier = .invalid
    private var startedAt: Date = Date()
    private var lastUpdateAt: Date = .distantPast

    private init() {}

    func requestNotificationPermission() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
    }

    func beginGeneration(modelName: String) {
        endBackgroundTask()
        bgTaskId = UIApplication.shared.beginBackgroundTask(withName: "SENAI.Generation") { [weak self] in
            Task { @MainActor in
                self?.endBackgroundTask()
            }
        }
        startedAt = Date()
        lastUpdateAt = .distantPast

        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if let existing = currentActivity {
            Task { await existing.end(nil, dismissalPolicy: .immediate) }
            currentActivity = nil
        }
        let attrs = SenGenerationAttributes(modelName: modelName)
        let state = SenGenerationAttributes.ContentState(
            stage: "Yanıt hazırlanıyor...",
            detail: "",
            isDone: false,
            startedAt: startedAt
        )
        do {
            currentActivity = try Activity.request(
                attributes: attrs,
                content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(180))
            )
        } catch {
            currentActivity = nil
        }
    }

    func updateGeneration(stage: String, detail: String = "") {
        guard let act = currentActivity else { return }
        let now = Date()
        guard now.timeIntervalSince(lastUpdateAt) >= 1.2 else { return }
        lastUpdateAt = now
        let state = SenGenerationAttributes.ContentState(
            stage: stage,
            detail: detail,
            isDone: false,
            startedAt: startedAt
        )
        Task {
            await act.update(ActivityContent(state: state, staleDate: Date().addingTimeInterval(180)))
        }
    }

    func finishGeneration(modelName: String, preview: String) {
        let cleanPreview = preview
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let snippet = String(cleanPreview.prefix(110))

        if let act = currentActivity {
            let finalState = SenGenerationAttributes.ContentState(
                stage: "Yanıt hazır ✓",
                detail: snippet,
                isDone: true,
                startedAt: startedAt
            )
            currentActivity = nil
            Task {
                await act.end(
                    ActivityContent(state: finalState, staleDate: nil),
                    dismissalPolicy: .after(Date().addingTimeInterval(6))
                )
            }
        }

        // Fire local notification if user left the app or locked the screen
        if UIApplication.shared.applicationState != .active, !snippet.isEmpty {
            let content = UNMutableNotificationContent()
            content.title = "SEN.AI (\(modelName)) yanıtı hazır"
            content.body = snippet
            content.sound = .default
            let req = UNNotificationRequest(
                identifier: "senai_done_\(UUID().uuidString.prefix(8))",
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(req)
        }

        endBackgroundTask()
    }

    func cancelGeneration() {
        if let act = currentActivity {
            currentActivity = nil
            Task { await act.end(nil, dismissalPolicy: .immediate) }
        }
        endBackgroundTask()
    }

    private func endBackgroundTask() {
        if bgTaskId != .invalid {
            UIApplication.shared.endBackgroundTask(bgTaskId)
            bgTaskId = .invalid
        }
    }
}
