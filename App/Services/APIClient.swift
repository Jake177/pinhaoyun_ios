import Foundation
import Observation
import Security

struct APIError: LocalizedError {
    let status: Int
    let message: String
    let code: String?
    var errorDescription: String? {
        switch code {
        case "UserNotConfirmedException": return String(localized: "Verify your email before signing in.")
        case "NotAuthorizedException": return String(localized: "Your email or password is incorrect, or your session has expired.")
        case "CodeMismatchException", "ExpiredCodeException": return String(localized: "The code is incorrect or has expired. Request a new one.")
        case "UsernameExistsException": return String(localized: "This email already has an account. Sign in instead.")
        case "InvalidPasswordException": return String(localized: "Use at least 8 characters with uppercase, lowercase, a number and a symbol.")
        default: return message
        }
    }
}

private struct APIResponseFailure: Decodable { let error: String?; let code: String? }

@MainActor @Observable final class APIClient {
    let baseURL: URL?
    var tokens: AuthTokens?
    var deletionReceipt: DeletionReceipt?
    var libraryRevision = 0
    private let network: URLSession
    private var refreshTask: Task<AuthTokens, Error>?
    private var sessionGeneration = 0
    private var accountKey: String { "session:" + (baseURL?.absoluteString ?? "unconfigured") }
    private var receiptKey: String { "deletion:" + (baseURL?.absoluteString ?? "unconfigured") }

    init(baseURL: URL? = nil) {
        let configured = baseURL ?? URL(string: Bundle.main.object(forInfoDictionaryKey: "PHAPIBaseURL") as? String ?? "")
        self.baseURL = configured?.host == nil ? nil : configured
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 30
        self.network = URLSession(configuration: configuration)
        tokens = try? Keychain.read(AuthTokens.self, account: accountKey)
        deletionReceipt = try? Keychain.read(DeletionReceipt.self, account: receiptKey)
    }
    func saveTokens(_ value: AuthTokens) throws {
        try Keychain.save(value, account: accountKey)
        tokens = value
    }
    func clearTokens() {
        sessionGeneration += 1
        refreshTask?.cancel(); refreshTask = nil
        Keychain.remove(account: accountKey); tokens = nil
    }
    func request<T: Decodable & Sendable>(_ path: String, method: String = "GET", body: [String: Any]? = nil, authenticated: Bool = true, retry: Bool = true) async throws -> T {
        try Task.checkCancellation()
        let generation = sessionGeneration
        guard let baseURL else { throw APIError(status: 503, message: String(localized: "The service is temporarily unavailable. Please try again later."), code: nil) }
        let suffix = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard let url = URL(string: suffix, relativeTo: baseURL.appendingPathComponent("/"))?.absoluteURL else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if authenticated {
            guard let tokens else { throw APIError(status: 401, message: String(localized: "Please sign in again."), code: nil) }
            request.setValue("Bearer " + tokens.idToken, forHTTPHeaderField: "Authorization")
            request.setValue(tokens.accessToken, forHTTPHeaderField: "X-Access-Token")
        }
        let (data, response) = try await network.data(for: request)
        try Task.checkCancellation()
        if authenticated, generation != sessionGeneration { throw CancellationError() }
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 401, authenticated, retry {
            do { try await refresh() }
            catch { if generation == sessionGeneration { clearTokens() }; throw error }
            return try await self.request(path, method: method, body: body, authenticated: authenticated, retry: false)
        }
        guard (200..<300).contains(http.statusCode) else {
            let failure = try? JSONDecoder().decode(APIResponseFailure.self, from: data)
            throw APIError(status: http.statusCode, message: failure?.error ?? String(localized: "The request failed. Please try again."), code: failure?.code)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
    func signIn(email: String, password: String) async throws {
        let result: AuthTokens = try await request("/api/mobile/auth/sign-in", method: "POST", body: ["email": email, "password": password], authenticated: false)
        sessionGeneration += 1
        refreshTask?.cancel(); refreshTask = nil
        try saveTokens(result)
    }
    func refresh() async throws {
        let generation = sessionGeneration
        if let task = refreshTask {
            let result = try await task.value
            guard generation == sessionGeneration else { throw CancellationError() }
            try saveTokens(result); return
        }
        guard let tokens else { throw URLError(.userAuthenticationRequired) }
        let task = Task<AuthTokens, Error> {
            try await request("/api/mobile/auth/refresh", method: "POST", body: ["refreshToken": tokens.refreshToken, "username": tokens.username], authenticated: false)
        }
        refreshTask = task
        defer { if generation == sessionGeneration { refreshTask = nil } }
        let result = try await task.value
        guard generation == sessionGeneration else { throw CancellationError() }
        try saveTokens(result)
    }
    func accept(_ policy: PolicyDocument) async throws {
        let _: OKResponse = try await request("/api/mobile/consent", method: "POST", body: Self.consentBody(policy))
        if var value = tokens { value.requiresConsent = false; try saveTokens(value) }
    }
    static func consentBody(_ policy: PolicyDocument) -> [String: Any] {
        ["acceptedTerms": true, "acknowledgedPrivacy": true, "termsVersion": policy.version, "privacyVersion": policy.version]
    }
    func signOut() async {
        let refreshToken = tokens?.refreshToken
        clearTokens()
        if let refreshToken {
            let _: OKResponse? = try? await request("/api/mobile/auth/sign-out", method: "POST", body: ["refreshToken": refreshToken], authenticated: false)
        }
    }
    func deleteAccount() async throws {
        guard let owner = tokens?.sub else { throw URLError(.userAuthenticationRequired) }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw Keychain.KeychainError.unavailable }
        let proof = Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let pending = deletionReceipt.flatMap { $0.ownerSub == owner && $0.state == "REQUESTING" ? $0 : nil }
        let intent = pending ?? DeletionReceipt(requestId: UUID().uuidString.lowercased(), receipt: proof, requestedAt: ISO8601DateFormatter().string(from: .now), deleteBy: ISO8601DateFormatter().string(from: .now.addingTimeInterval(30 * 86400)), state: "REQUESTING", ownerSub: owner)
        // Save the proof before sending: a dropped response must not lose the receipt.
        try Keychain.save(intent, account: receiptKey)
        deletionReceipt = intent
        var receipt: DeletionReceipt = try await request("/api/user/delete-account", method: "POST", body: ["confirm": true, "requestId": intent.requestId, "receipt": intent.receipt])
        receipt.ownerSub = owner
        try? Keychain.save(receipt, account: receiptKey)
        deletionReceipt = receipt
        clearTokens()
    }
    func deletionStatus() async throws -> DeletionStatus {
        guard let receipt = deletionReceipt else { throw URLError(.userAuthenticationRequired) }
        return try await request("/api/user/deletion-status", method: "POST", body: ["requestId": receipt.requestId, "receipt": receipt.receipt], authenticated: false)
    }
    var hasSavedDeletionReceipt: Bool { (try? Keychain.read(DeletionReceipt.self, account: receiptKey)) != nil }
    func dismissReceipt() { deletionReceipt = nil }
    func restoreReceipt() { deletionReceipt = try? Keychain.read(DeletionReceipt.self, account: receiptKey) }
    func download(_ url: URL, extension ext: String) async throws -> URL {
        let (temporary, response) = try await network.download(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MediaExports", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let output = folder.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
        try FileManager.default.moveItem(at: temporary, to: output)
        return output
    }
}
