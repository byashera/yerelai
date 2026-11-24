import ActivityKit
import SwiftUI
import WidgetKit

@main
struct SENAIWidgetsBundle: WidgetBundle {
    var body: some Widget {
        SenGenerationLiveActivity()
    }
}

struct SenGenerationLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SenGenerationAttributes.self) { context in
            // Lock Screen / Notification Banner Live Activity
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: context.state.isDone
                                    ? [Color.green, Color.teal]
                                    : [Color.blue, Color.indigo, Color.purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                    Image(systemName: context.state.isDone ? "checkmark" : "sparkle")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("SEN.AI")
                            .font(.subheadline.weight(.bold))
                        Text(context.attributes.modelName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background { Capsule().fill(Color.primary.opacity(0.08)) }
                        Spacer()
                        if !context.state.isDone {
                            Text(context.state.startedAt, style: .timer)
                                .font(.caption2.monospacedDigit().weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(context.state.stage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(context.state.isDone ? .green : .blue)
                    if !context.state.detail.isEmpty {
                        Text(context.state.detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .padding(14)
            .activityBackgroundTint(Color(.systemBackground).opacity(0.88))
            .activitySystemActionForegroundColor(.blue)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: context.state.isDone ? "checkmark.circle.fill" : "sparkle")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(context.state.isDone ? .green : .cyan)
                        Text(context.attributes.modelName)
                            .font(.caption.weight(.bold))
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.isDone {
                        Text("Hazır")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.green)
                    } else {
                        Text(context.state.startedAt, style: .timer)
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.state.stage)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(context.state.isDone ? .green : .cyan)
                        if !context.state.detail.isEmpty {
                            Text(context.state.detail)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
                }
            } compactLeading: {
                Image(systemName: context.state.isDone ? "checkmark.circle.fill" : "sparkle")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(context.state.isDone ? .green : .cyan)
            } compactTrailing: {
                Text(context.state.isDone ? "Hazır" : context.attributes.modelName)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(context.state.isDone ? .green : .primary)
                    .lineLimit(1)
            } minimal: {
                Image(systemName: context.state.isDone ? "checkmark" : "sparkle")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(context.state.isDone ? .green : .cyan)
            }
        }
    }
}
