import Foundation

struct MediaItem: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let type: String
    var originalName: String?
    var thumbnailUrl: URL?
    var thumbnailUrlAlt: URL?
    var originalUrl: URL?
    var originalPhotoUrl: URL?
    var liveVideoUrl: URL?
    var mediaAt: String?
    var captureTime: String?
    var fileLastModified: String?
    var createdAt: String?
    var size: Int64?
    var width: Int?
    var height: Int?
    var durationSec: Double?
    var captureCity: String?
    var deviceModel: String?
    var status: String?
    var isPhoto: Bool { type == "PHOTO" }
    var isLivePhoto: Bool { liveVideoUrl != nil }
    var title: String { originalName ?? (isPhoto ? String(localized: "Photo") : String(localized: "Video")) }
    var date: Date {
        for value in [mediaAt, captureTime, fileLastModified, createdAt].compactMap({ $0 }) {
            if let date = Self.parseDate(value) { return date }
        }
        return .distantPast
    }
    static func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
struct LibraryPage: Decodable, Sendable { let videos: [MediaItem]; let nextCursor: String?; let hasMore: Bool }
struct MediaURLs: Decodable, Sendable {
    let originalUrl: URL?; let originalPhotoUrl: URL?; let thumbnailUrl: URL?; let liveVideoUrl: URL?; let expiresAt: String
}
struct UserProfile: Decodable, Sendable {
    let email: String
    let preferredUsername: String?
    let planDisplayName: String?
    let usedBytes: Int64
    let quotaBytes: Int64
    let photoCount: Int?
    let videosCount: Int?
}
struct AuthTokens: Codable, Sendable {
    let idToken: String; let accessToken: String; let refreshToken: String
    let expiresIn: Int; let username: String; let sub: String; let email: String
    var requiresConsent: Bool
}
struct PolicyDocument: Decodable, Sendable {
    let version: String; let isDraft: Bool; let terms: [String: String]; let privacy: [String: String]
    let reading: PolicyReading?
    var language: String { Locale.preferredLanguages.first?.hasPrefix("zh") == true ? "zh" : "en" }
    var termsText: String { terms[language] ?? terms["en"] ?? "" }
    var privacyText: String { privacy[language] ?? privacy["en"] ?? "" }
}
struct PolicyReading: Decodable, Sendable { let terms: [String: PolicyReadingText]; let privacy: [String: PolicyReadingText] }
struct PolicyReadingText: Decodable, Sendable { let title: String; let sections: [PolicyReadingSection] }
struct PolicyReadingSection: Decodable, Sendable { let title: String; let text: String }
struct DeletionReceipt: Codable, Sendable {
    let requestId: String; let receipt: String; let requestedAt: String; let deleteBy: String; let state: String
    var ownerSub: String? = nil
}
struct DeletionStatus: Decodable, Sendable { let state: String; let requestedAt: String; let deleteBy: String; let completedAt: String? }
struct OKResponse: Decodable, Sendable { var ok: Bool?; var userConfirmed: Bool? }
struct UploadStart: Decodable, Sendable { let duplicate: Bool; let uploadId: String?; let key: String?; let bucket: String?; let photoId: String?; let skipped: Bool?; let skipReason: String?; let resumed: Bool? }
struct UploadFinish: Decodable, Sendable { let ok: Bool; let duplicate: Bool?; let photoId: String? }
struct PartURL: Decodable, Sendable { let uploadUrl: URL }
struct UploadedPart: Codable, Sendable { let partNumber: Int; let etag: String }
struct UploadStatus: Decodable, Sendable { let parts: [UploadedPart]; let completed: Bool }
