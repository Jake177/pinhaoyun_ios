import Foundation
import CryptoKit
import UIKit

@MainActor enum BackupDiagnostics {
    static func url(key: String) -> URL {
        let name = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("BackupDiagnostics", isDirectory: true).appendingPathComponent(name + ".json")
    }
    static func record(key: String, status: String, assets: [BackupAsset], network: String, window: BackupWindow, backgroundProcessing: Bool) {
        let file = url(key: key)
        var document = (try? Data(contentsOf: file)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        var events = document["events"] as? [[String: Any]] ?? []
        let parts = Calendar.autoupdatingCurrent.dateComponents([.year, .month, .day], from: .now)
        let day = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        let completed = assets.filter { $0.state == "completed" }.count
        let pending = assets.filter { ["pending", "queued"].contains($0.state) }.count
        let failed = assets.filter { $0.state == "failed" }.count
        let execution = UIApplication.shared.applicationState == .active ? "foreground" : (backgroundProcessing ? "background-processing" : "background-event")
        let signature = "\(day)|\(status)|\(completed)|\(pending)|\(failed)|\(network)|\(window.enabled)|\(window.start)|\(window.end)|\(TimeZone.autoupdatingCurrent.identifier)|\(execution)"
        if events.last?["signature"] as? String == signature { return }
        #if targetEnvironment(simulator)
        let origin = "simulator"
        #else
        let origin = "physical-device"
        #endif
        let event: [String: Any] = ["at": ISO8601DateFormatter().string(from: .now), "day": day, "origin": origin,
            "osVersion": UIDevice.current.systemVersion, "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            "timeZone": TimeZone.autoupdatingCurrent.identifier, "status": status, "network": network,
            "execution": execution,
            "completed": completed, "pending": pending, "failed": failed, "windowEnabled": window.enabled,
            "startMinute": window.start, "endMinute": window.end, "signature": signature]
        events.append(event)
        var days = document["days"] as? [String: [String: Any]] ?? [:]; days[day] = event
        for old in days.keys.sorted().dropLast(30) { days.removeValue(forKey: old) }
        document = ["formatVersion": 1, "environment": "isolated-development", "days": days, "events": Array(events.suffix(500))]
        do {
            let directory = file.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            var excluded = directory; var values = URLResourceValues(); values.isExcludedFromBackup = true; try excluded.setResourceValues(values)
            try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys]).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch { /* Diagnostics must not interrupt backup. */ }
    }
}
