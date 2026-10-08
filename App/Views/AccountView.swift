import SwiftUI

struct AccountView: View {
    @Environment(APIClient.self) private var api
    @Environment(TransferManager.self) private var transfers
    @State private var profile: UserProfile?
    @State private var policy: PolicyDocument?
    @State private var legal: PolicySheet?
    @State private var error: String?
    @State private var signingOut = false
    @State private var loading = false
    @State private var policyLoading = false
    @State private var policyError: String?
    @State private var confirmingSignOut = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(profile?.preferredUsername ?? api.tokens?.email ?? "PinHaoYun", systemImage: "person.crop.circle").font(.headline)
                    if let email = api.tokens?.email { Text(email).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled) }
                }
                if let profile {
                    Section("Storage") {
                        ProgressView(value: min(1, Double(profile.usedBytes) / Double(max(1, profile.quotaBytes)))).accessibilityLabel("Storage used")
                        Text(String(format: String(localized: "%@ of %@ used"), profile.usedBytes.formatted(.byteCount(style: .file)), profile.quotaBytes.formatted(.byteCount(style: .file)))).font(.subheadline)
                        LabeledContent("Plan", value: profile.planDisplayName ?? String(localized: "Free"))
                        LabeledContent("Photos", value: String(profile.photoCount ?? 0)); LabeledContent("Videos", value: String(profile.videosCount ?? 0))
                    }
                }
                if loading && profile == nil { Section { ProgressView("Loading your account") } }
                if let error { Section { Text(error).foregroundStyle(.red); Button("Try again") { Task { await load() } } } }
                Section("Privacy and account") {
                    if let policy {
                        Button("Terms of use") { legal = PolicySheet(kind: .terms, document: policy) }
                        Button("Privacy notice") { legal = PolicySheet(kind: .privacy, document: policy) }
                    }
                    if policyLoading && policy == nil { ProgressView("Loading terms and privacy notice") }
                    if let policyError {
                        Text(policyError).foregroundStyle(.red)
                        Button("Try again") { Task { await loadPolicies() } }
                    }
                    NavigationLink("Delete account") { DeleteAccountView() }.foregroundStyle(.red)
                }
                Section {
                    Button(action: signOut) { HStack { Text("Sign out"); Spacer(); if signingOut { ProgressView() } } }.disabled(signingOut)
                } footer: { Text("PinHaoYun · Beta 0.1\nYour device's Photos library is never removed by account deletion.") }
            }
            .navigationTitle("Account")
            .sheet(item: $legal) { PolicyTextView(sheet: $0) }
            .confirmationDialog("Sign out and cancel unfinished uploads?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
                Button("Cancel uploads and sign out", role: .destructive, action: performSignOut)
            } message: { Text("Unfinished uploads will be cancelled. Add them again after signing in. Photos on your device, completed cloud files and transfer history are kept.") }
            .task { await load() }
            .task { await loadPolicies() }
            .refreshable { await load() }
        }
    }
    private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do { profile = try await api.request("/api/user/profile"); error = nil }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func loadPolicies() async {
        policyLoading = true; policyError = nil
        defer { policyLoading = false }
        do { policy = try await api.request("/api/mobile/policies", authenticated: false) }
        catch { if !Task.isCancelled { policyError = error.localizedDescription } }
    }
    private func signOut() {
        if transfers.records().contains(where: { $0.ownerSub == api.tokens?.sub && !$0.isFinished }) { confirmingSignOut = true }
        else { performSignOut() }
    }
    private func performSignOut() {
        signingOut = true
        Task { await transfers.cancelUnfinishedForSignOut(); await api.signOut(); signingOut = false }
    }
}
private struct DeleteAccountView: View {
    @Environment(APIClient.self) private var api
    @Environment(TransferManager.self) private var transfers
    @State private var password = ""
    @State private var confirming = false
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        Form {
            Section {
                Text("Delete your PinHaoYun account?").font(.title2.bold())
                Text("This deletes the account shared by Web and iOS. Access stops immediately and cloud photos, videos and account data will be deleted within 30 days.")
                Text("Photos on your device are kept. Download any cloud originals you need before continuing.").foregroundStyle(.secondary)
            }
            Section("Confirm your identity") {
                SecureField("Current password", text: $password).textContentType(.password)
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
            Section {
                Button(role: .destructive) { confirming = true } label: { HStack { Text("Delete account and cloud data"); Spacer(); if busy { ProgressView() } } }.disabled(password.isEmpty || busy)
            }
        }
        .navigationTitle("Delete account").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Permanently delete your account?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Confirm account deletion", role: .destructive, action: delete)
        } message: { Text("There is no recovery promise after deletion begins.") }
    }
    private func delete() {
        guard let email = api.tokens?.email else { return }
        busy = true
        Task {
            do { try await api.signIn(email: email, password: password); password = ""; await transfers.clearForSignOut(); try await api.deleteAccount() }
            catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}
