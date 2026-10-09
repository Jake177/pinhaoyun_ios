import Foundation
import SwiftData

struct UploadComponent: Codable, Sendable {
    var filePath: String
    var fileName: String
    var contentType: String
    var size: Int64
    var mediaType: String
    var mediaRole: String
    var photoId: String?
    var contentHash: String?
    var uploadId: String?
    var key: String?
    var bucket: String?
    var parts: [UploadedPart] = []
    var remoteCompleted = false
    var notified = false
    var skipped = false
    var requestId: String?
}
@Model final class TransferRecord {
    @Attribute(.unique) var id: UUID
    var ownerSub: String
    var displayName: String
    var createdAt: Date
    var state: String
    var message: String?
    var componentsData: Data
    var componentIndex: Int
    var completedBytes: Int64
    var totalBytes: Int64
    var source: String = "manual"
    var environment: String = ""
    var localAssetIdentifier: String?
    var startedAt: Date?
    var capturedAt: Date?
    var retryAfter: Date?
    var retryCount: Int = 0
    var pauseReason: String?
    var skipReason: String?
    var activeTaskTag: String?
    init(ownerSub: String, displayName: String, components: [UploadComponent]) throws {
        id = UUID(); self.ownerSub = ownerSub; self.displayName = displayName
        createdAt = .now; state = "waiting"; componentIndex = 0; completedBytes = 0
        totalBytes = components.reduce(0) { $0 + $1.size }
        componentsData = try JSONEncoder().encode(components)
    }
    var progress: Double { totalBytes > 0 ? min(1, Double(completedBytes) / Double(totalBytes)) : 0 }
    var components: [UploadComponent] {
        get { (try? JSONDecoder().decode([UploadComponent].self, from: componentsData)) ?? [] }
        set { componentsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
    var isFinished: Bool { ["completed", "cancelled", "skipped"].contains(state) }
    var stateLabel: String {
        switch state {
        case "uploading": String(localized: "Uploading")
        case "waitingForNetwork": String(localized: "Waiting for network")
        case "finalizing": String(localized: "Finishing")
        case "completed": String(localized: "Completed")
        case "failed": String(localized: "Needs attention")
        case "cancelled": String(localized: "Cancelled")
        case "paused": String(localized: "Paused")
        case "retryWaiting": String(localized: "Retrying later")
        case "skipped": String(localized: "Skipped")
        default: String(localized: "Waiting")
        }
    }
}
