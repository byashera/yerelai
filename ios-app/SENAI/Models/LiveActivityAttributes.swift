import ActivityKit
import Foundation

struct SenGenerationAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var stage: String
        var detail: String
        var isDone: Bool
        var startedAt: Date
    }

    var modelName: String
}
