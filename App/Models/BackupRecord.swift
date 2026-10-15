import Foundation
import SwiftData

@Model final class BackupSettings {
    @Attribute(.unique) var key: String
    var enabled = false
    var scope = "new"
    var videos = false
    var cellular = false
    var windowEnabled = false
    var startMinute = 120
    var endMinute = 360
    var baselineReady = false
    var scanToken: Data?
    var lastCheckedAt: Date?
    init(key: String) { self.key = key }
}

@Model final class BackupAsset {
    @Attribute(.unique) var key: String
    var settingsKey: String
    var assetIdentifier: String
    var kind: String
    var state: String
    var message: String?
    var transferID: UUID?
    var presentAtActivation: Bool = false
    var startedAt: Date?
    var preparationFolder: String?
    var createdAt: Date
    init(settingsKey: String, assetIdentifier: String, kind: String, baseline: Bool = false, presentAtActivation: Bool = false) {
        self.settingsKey = settingsKey; self.assetIdentifier = assetIdentifier; self.kind = kind
        key = settingsKey + "|" + assetIdentifier; state = baseline ? "baseline" : "pending"; createdAt = .now
        self.presentAtActivation = presentAtActivation
    }
}

struct BackupWindow: Sendable {
    let enabled: Bool
    let start: Int
    let end: Int
    var valid: Bool { !enabled || ((0..<1440).contains(start) && (0..<1440).contains(end) && start != end) }
    func contains(_ date: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        guard enabled else { return true }
        guard valid else { return false }
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        return start < end ? minute >= start && minute < end : minute >= start || minute < end
    }
    func nextStart(after date: Date, calendar: Calendar = .autoupdatingCurrent) -> Date? {
        guard enabled, valid else { return nil }
        return calendar.nextDate(after: date, matching: DateComponents(hour: start / 60, minute: start % 60), matchingPolicy: .nextTime, repeatedTimePolicy: .first)
    }
}
